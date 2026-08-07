#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write). After a .gd file is written, run the
# deterministic GDScript gates and feed any failure back to the model as a
# blocking reason so the edit is not silently accepted with violations.
#
# Three gates, cheapest first:
#   1. gdscript-formatter --check   — official style-guide formatting
#   2. gdscript-formatter lint       — its ~18 generic lint rules
#   3. gd-lint.py                    — the bespoke ~/.claude/rules/gdscript
#                                      syntactic subset (H1/H2/C1/C3/D7b/S6b/S6c/…)
#
# The judgment-level corpus (engine-bug lifecycle, DOD D1-D11) has no linter —
# enforce that via the Stop-hook gdscript-reviewer, not here.
#
# DIFF-AWARE: for a file already tracked at HEAD, findings are filtered to the
# lines the current edit actually changed (working tree vs HEAD). Pre-existing
# violations on untouched lines do NOT block — you only own what you touch. New
# / untracked files are enforced in full. This lets the gate ride on top of a
# legacy codebase that predates it without forcing a whole-file reformat every
# time one function is edited. Keep a full-file run (CI, or the linter over the
# whole tree) as the authoritative gate.
#
# Output: {"decision":"block","reason":...} on any gate failure, else exit 0.
# Fails OPEN on tooling errors (missing binary, unreadable input, formatter
# panic) — a broken gate must never wedge the session.

set -u

# Path to the package's gd-lint.py. Override with GDLINT, or symlink the linter
# to ~/.claude/hooks/gd-lint.py (the Claude Code convention used below).
GDLINT="${GDLINT:-$HOME/.claude/hooks/gd-lint.py}"
FORMATTER="$(command -v gdscript-formatter || true)"

# --- read hook payload from stdin ---
payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$file" ] && exit 0
case "$file" in
  *.gd) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# --- diff-awareness: which lines did this edit change? ---
# diff_aware=1 only when the file is tracked at HEAD; then changed_lines holds the
# working-tree-vs-HEAD added/modified line numbers. Untracked/new file or no git
# => diff_aware=0 => enforce the whole file.
diff_aware=0
changed_lines=""
repo_root=""
rel=""
file_dir="$(dirname "$file")"
if command -v git >/dev/null 2>&1 && repo_root="$(git -C "$file_dir" rev-parse --show-toplevel 2>/dev/null)"; then
  # --full-name yields the repo-relative path git itself uses, so a symlinked or
  # otherwise non-canonical "$file" still resolves for the later "HEAD:$rel" read.
  # --error-unmatch makes an untracked file print nothing -> rel empty -> full-file mode.
  rel="$(git -C "$repo_root" ls-files --full-name --error-unmatch -- "$file" 2>/dev/null | head -1)"
  # HEAD must resolve too: in a repo with no commits yet, "diff HEAD" errors and
  # would yield an empty changed set — which filters away EVERY finding instead of
  # none. No HEAD => nothing to grandfather anyway => enforce the whole file.
  if [ -n "$rel" ] && git -C "$repo_root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    diff_aware=1
    changed_lines="$(git -C "$repo_root" diff -U0 --no-color HEAD -- "$file" 2>/dev/null | awk '
      /^@@/ {
        plus = $3            # +start,count
        sub(/^\+/, "", plus)
        n = split(plus, a, ",")
        start = a[1] + 0
        cnt = (n > 1 ? a[2] + 0 : 1)
        for (i = 0; i < cnt; i++) print start + i
      }')"
  fi
fi

# line_changed N -> 0 if line N is in the changed set (or diff_aware off).
line_changed() {
  [ "$diff_aware" = 0 ] && return 0
  printf '%s\n' "$changed_lines" | grep -qx -- "$1"
}

# filter_findings: stdin = tool findings (one per line, "<file>:<line>:<rest>").
# Keeps a finding only when its line is in the changed set. Lines that don't
# carry a "<file>:<num>:" prefix (summaries/headers) are dropped so they can't
# false-trigger the block grep. With diff_aware off, everything numeric passes.
filter_findings() {
  while IFS= read -r ln; do
    case "$ln" in
      "$file":*)
        rest="${ln#"$file":}"
        num="${rest%%:*}"
        case "$num" in
          ''|*[!0-9]*) : ;;                       # not a line-anchored finding — drop
          *) line_changed "$num" && printf '%s\n' "$ln" ;;
        esac
        ;;
      *) : ;;                                       # non-finding noise — drop
    esac
  done
}

reason=""

# --- gates 1 + 2: gdscript-formatter (skip silently if absent) ---
if [ -n "$FORMATTER" ]; then
  # Gate 1 — formatting. Diff-aware: only flag when the CURRENT file is unformatted
  # AND the HEAD version was already formatted (i.e. this edit introduced the drift).
  # A file that was already unformatted at HEAD is grandfathered. A formatter panic
  # (known ternary-corruption bug) fails open rather than mislabeling "not formatted".
  fmt_stderr="$("$FORMATTER" --check "$file" 2>&1 >/dev/null)"
  fmt_rc=$?
  if printf '%s' "$fmt_stderr" | grep -qi 'panic'; then
    : # formatter crashed — fail open, do not gate on a broken tool
  elif [ "$fmt_rc" -ne 0 ]; then
    head_unformatted=0
    if [ "$diff_aware" = 1 ]; then
      # gdscript-formatter takes .gd paths only — it rejects "-"/stdin outright,
      # so the HEAD blob has to land in a real .gd file before it can be checked.
      head_dir="$(mktemp -d 2>/dev/null || true)"
      if [ -n "$head_dir" ]; then
        if git -C "$repo_root" show "HEAD:$rel" > "$head_dir/head.gd" 2>/dev/null \
          && [ -s "$head_dir/head.gd" ] \
          && ! "$FORMATTER" --check "$head_dir/head.gd" >/dev/null 2>&1; then
          head_unformatted=1   # already dirty at HEAD — grandfather, this edit didn't cause it
        fi
        rm -rf "$head_dir"
      fi
    fi
    if [ "$head_unformatted" = 0 ]; then
      reason="FORMAT: not formatted — run: gdscript-formatter \"$file\""
    fi
  fi

  # Gate 2 — lint. Disable max-line-length: --check already enforces style-guide
  # wrapping, and residual long lines are usually unwrappable (long strings /
  # res:// paths). White-box tests legitimately reach internals their subject
  # exposes no public entry for, and the test runner is their real gate, so
  # private-access is exempt under tests/.
  disable_rules="max-line-length"
  case "$file" in
    */tests/*) disable_rules="${disable_rules},private-access" ;;
  esac
  # Project-local rule disables: a repo may keep .claude/gdscript-formatter-disable
  # (one rule name per line, # comments allowed) listing rules that conflict with
  # DELIBERATE, documented conventions of that codebase (protocol-mirrored names,
  # codegen-emitted identifiers, a _-prefix privacy convention, type-alias consts).
  # gdscript-formatter has no config-file support, so the hook carries it. Scoped
  # to the repo — other projects keep the full ruleset.
  if [ -n "$repo_root" ] && [ -f "$repo_root/.claude/gdscript-formatter-disable" ]; then
    proj_disable="$(grep -vE '^[[:space:]]*(#|$)' "$repo_root/.claude/gdscript-formatter-disable" | paste -sd, -)"
    [ -n "$proj_disable" ] && disable_rules="${disable_rules},${proj_disable}"
  fi
  lint_raw="$("$FORMATTER" lint --disable "$disable_rules" "$file" 2>&1 || true)"
  if printf '%s' "$lint_raw" | grep -qi 'panic'; then
    lint_raw=""   # formatter panic — fail open
  fi
  lint_out="$(printf '%s\n' "$lint_raw" | filter_findings)"
  if [ -n "$lint_out" ]; then
    [ -n "$reason" ] && reason="${reason}"$'\n'
    reason="${reason}LINT:"$'\n'"${lint_out}"
  fi
fi

# --- gate 3: bespoke rule linter (skip silently if python3 / script absent) ---
# gd-lint tags advisory findings with ' [advisory]' and exits non-zero only on
# BLOCKING findings. Split the two: blocking → the block reason, advisory → a
# non-blocking note. Both are diff-filtered to the changed lines.
advisory=""
if [ -f "$GDLINT" ] && command -v python3 >/dev/null 2>&1; then
  rules_out="$(python3 "$GDLINT" "$file" 2>/dev/null || true)"
  if [ -n "$rules_out" ]; then
    blocking_rules="$(printf '%s\n' "$rules_out" | grep -v '\[advisory\]' | sed '/^$/d' | filter_findings || true)"
    advisory="$(printf '%s\n' "$rules_out" | grep '\[advisory\]' | filter_findings || true)"
    if [ -n "$blocking_rules" ]; then
      [ -n "$reason" ] && reason="${reason}"$'\n'
      reason="${reason}RULES (~/.claude/rules/gdscript):"$'\n'"${blocking_rules}"
    fi
  fi
fi

if [ -n "$reason" ]; then
  # blocking failure — advisory notes ride along inside the block reason
  [ -n "$advisory" ] && reason="${reason}"$'\n'"ADVISORY (not blocking):"$'\n'"${advisory}"
  jq -n --arg r "GDScript gate failed on $file. Fix before continuing:"$'\n'"$reason" \
    '{decision:"block", reason:$r}'
  exit 0
fi

if [ -n "$advisory" ]; then
  # advisory-only — surface as a non-blocking message, never block the edit
  jq -n --arg m "GDScript advisory on $file (loop-idiom, not blocking):"$'\n'"$advisory" \
    '{systemMessage:$m}'
fi
exit 0
