#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write). After a .gd file is written, run the
# deterministic GDScript gates and feed any failure back to the model as a
# blocking reason so the edit is not silently accepted with violations.
#
# Three gates, cheapest first:
#   1. gdscript-formatter --check   — official style-guide formatting
#   2. gdscript-formatter lint       — its ~18 generic lint rules
#   3. gd-lint.py                    — the bespoke ~/.claude/rules/gdscript
#                                      syntactic subset (H1/H2/S1/C1/D7b)
#
# The judgment-level corpus (engine-bug lifecycle, DOD D1-D11) has no linter —
# enforce that via the Stop-hook gdscript-reviewer, not here.
#
# Output: {"decision":"block","reason":...} on any gate failure, else exit 0.
# Fails OPEN on tooling errors (missing binary, unreadable input) — a broken
# gate must never wedge the session.

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

reason=""

# --- gates 1 + 2: gdscript-formatter (skip silently if absent) ---
if [ -n "$FORMATTER" ]; then
  if ! "$FORMATTER" --check "$file" >/dev/null 2>&1; then
    reason="FORMAT: not formatted — run: gdscript-formatter \"$file\""
  fi
  # Disable max-line-length: --check already enforces style-guide wrapping, and
  # residual long lines are usually unwrappable (long strings / res:// paths) —
  # flagging them is noise the model can't act on.
  lint_out="$("$FORMATTER" lint --disable max-line-length "$file" 2>&1 || true)"
  if printf '%s' "$lint_out" | grep -qiE 'error|warn|:[0-9]+:|rule'; then
    [ -n "$reason" ] && reason="${reason}"$'\n'
    reason="${reason}LINT:"$'\n'"${lint_out}"
  fi
fi

# --- gate 3: bespoke rule linter (skip silently if python3 / script absent) ---
# gd-lint tags advisory findings with ' [advisory]' and exits non-zero only on
# BLOCKING findings. Split the two: blocking → the block reason, advisory → a
# non-blocking note.
advisory=""
if [ -f "$GDLINT" ] && command -v python3 >/dev/null 2>&1; then
  rules_out="$(python3 "$GDLINT" "$file" 2>/dev/null || true)"
  if [ -n "$rules_out" ]; then
    blocking_rules="$(printf '%s\n' "$rules_out" | grep -v '\[advisory\]' | sed '/^$/d' || true)"
    advisory="$(printf '%s\n' "$rules_out" | grep '\[advisory\]' || true)"
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
