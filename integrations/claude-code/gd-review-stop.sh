#!/usr/bin/env bash
# Stop hook — severity-gated gdscript-reviewer pass over .gd files changed this
# session. The judgment-tier complement to gd-check.sh (which catches the
# deterministic syntactic rules at edit time). This tier targets the engine-bug
# rules that crash / leak / corrupt and can only be judged, not pattern-matched.
#
# Policy:
#   - Review runs via `claude -p` ONLY when changed .gd content differs from the
#     last reviewed state (content hash), so idle turns cost nothing.
#   - CRITICAL findings (runtime crash/leak/corruption) → decision:block, forcing
#     a fix before the turn can end. NOT stamped, so it re-blocks until resolved.
#   - Advisory findings (style / DOD / typing) → non-blocking systemMessage.
#
# Safety:
#   - GD_REVIEW_NESTED guard: the nested `claude -p` would otherwise re-fire this
#     same Stop hook → infinite recursion. The guard makes the nested run a no-op.
#   - Fails OPEN on every error path (no git, no claude, bad JSON) — a review
#     gate must never wedge the session.

set -u

# --- recursion guard: nested `claude -p` must not re-enter this hook ---
[ -n "${GD_REVIEW_NESTED:-}" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
cd "$cwd" 2>/dev/null || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" 2>/dev/null || exit 0

# --- gather changed + staged + untracked .gd (bounded) ---
# MAX_FILES is a review-quality bound, not just a cost one: a pass that exceeds
# the model's context dies mid-review with an autocompact-thrashing API error,
# and the turn then ends with no independent opinion at all. A partial review
# that finishes beats a whole-changeset review that crashes.
MAX_FILES=${GD_REVIEW_MAX_FILES:-12}
MAX_LINES_PER_FILE=${GD_REVIEW_MAX_LINES:-400}
MAX_INPUT_BYTES=${GD_REVIEW_MAX_BYTES:-60000}

changed="$(
  {
    git diff --name-only -- '*.gd'
    git diff --name-only --cached -- '*.gd'
    git ls-files --others --exclude-standard -- '*.gd'
  } 2>/dev/null | sort -u | head -"$MAX_FILES"
)"
[ -z "$changed" ] && exit 0

# --- dedup by content hash: skip if same as last reviewed state ---
stamp="$(git rev-parse --git-dir 2>/dev/null)/gd-review-stamp"
hash="$(printf '%s\n' "$changed" | xargs -r cat 2>/dev/null | sha1sum | cut -d' ' -f1)"
[ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ] && exit 0

command -v claude >/dev/null 2>&1 || { echo "$hash" > "$stamp"; exit 0; }

# --- assemble review input (diff hunks, bounded) ---
# Send the DIFF, not whole files. A 3,000-line player.gd whose changed surface is
# 40 lines used to arrive in full; thirty of those was the oversized-input crash.
# Untracked files have no diff, so they go in whole (still line-capped).
# Bounded loop: at most MAX_FILES iterations, and it stops adding once the total
# passes MAX_INPUT_BYTES, naming what it dropped rather than truncating silently.
input=""
skipped=""
bytes=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    body="$(git diff HEAD -U3 -- "$f" 2>/dev/null | sed -n "1,${MAX_LINES_PER_FILE}p")"
    label="DIFF"
  else
    [ -f "$f" ] || continue
    body="$(sed -n "1,${MAX_LINES_PER_FILE}p" "$f" 2>/dev/null)"
    label="NEW FILE"
  fi
  [ -z "$body" ] && continue
  chunk="$(printf '#### %s: %s\n%s\n\n' "$label" "$f" "$body")"
  if [ $((bytes + ${#chunk})) -gt "$MAX_INPUT_BYTES" ] && [ -n "$input" ]; then
    skipped="$skipped $f"
    continue
  fi
  input="$input$chunk"
  bytes=$((bytes + ${#chunk}))
done <<EOF
$changed
EOF
[ -z "$input" ] && { echo "$hash" > "$stamp"; exit 0; }
[ -n "$skipped" ] && input="$input
#### NOT INCLUDED (input budget):$skipped
"

rubric='You are gdscript-reviewer. Review the GDScript changes below against the Godot engine-bug rules. Input is unified diffs (added lines start with +); files marked NEW FILE are untracked and shown whole. Judge the changed lines and what they break; do not flag pre-existing lines that this change did not touch. Output ONLY compact JSON, no prose: {"critical":[{"file":"","line":0,"rule":"","why":""}],"advisory":[{"file":"","line":0,"rule":"","why":""}]}. CRITICAL = will crash, leak, or corrupt at runtime ONLY: C2/C2a static shared-mutable Array/Dict not made read_only; C3 typed .filter()/.map() assigned without .assign(); C5 await on a Node then use without is_instance_valid(); C7 RefCounted circular ref leak; C8 freed instance-id reused without validity AND type check; C11 sort_custom comparator using <= instead of strict <; C12 assert() used for runtime validation (stripped in release); C17 .tres<->.tscn preload cycle. Everything else (typing, style, DOD shape, naming) goes in advisory, never critical. Use empty arrays when none. Be conservative: if unsure an issue truly crashes/leaks/corrupts, put it in advisory.'

# --settings, not --bare. `--bare` ("minimal mode: skip hooks, LSP, plugin") was
# the obvious way to keep the nested run cheap and non-recursive, but on Claude
# Code 2.1.229 it exits 1 with "Not logged in · Please run /login" — with or
# without ANTHROPIC_BASE_URL set, while a plain `claude -p` on the same host
# authenticates fine. Whatever bare mode skips, it includes the credential path.
# The failure was invisible: the error string parsed as no findings, so this
# whole tier failed open on every run and the stamp was written as if a clean
# review had happened. `--settings '{"disableAllHooks":true}'` buys the same
# hook-skipping and authenticates.
#
# GD_REVIEW_NESTED=1 is still the recursion guard and is the one that matters —
# it makes this script a no-op in the child regardless of hook settings.
#
# --model: this is a fresh `claude -p` session, not a subagent, so without it
# the gate inherits the host's default model — Opus on a machine that sets one,
# for a fixed-rubric classification into two JSON arrays. GD_REVIEW_MODEL lets a
# host put this tier back up (or further down) without editing the script.
verdict="$(printf '%s' "$input" | GD_REVIEW_NESTED=1 timeout 150 \
  claude -p --settings '{"disableAllHooks":true}' --model "${GD_REVIEW_MODEL:-sonnet}" \
  --append-system-prompt "$rubric" 2>/dev/null)"

# strip any code fences the model may wrap around the JSON
verdict="$(printf '%s' "$verdict" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')"

crit="$(printf '%s' "$verdict" | jq -c '.critical // []' 2>/dev/null)"
if [ -z "$crit" ] || [ "$crit" = "null" ]; then
  echo "$hash" > "$stamp"          # unparseable → fail open, don't re-run on same content
  exit 0
fi

ncrit="$(printf '%s' "$crit" | jq 'length' 2>/dev/null || echo 0)"
if [ "${ncrit:-0}" -gt 0 ]; then
  # do NOT stamp — keep blocking until the content changes (i.e. gets fixed)
  body="$(printf '%s' "$crit" | jq -r '.[] | "  \(.file):\(.line) [\(.rule)] \(.why)"' 2>/dev/null)"
  jq -n --arg r "gdscript-reviewer: CRITICAL engine-bug issue(s) — fix before stopping:"$'\n'"$body" \
    '{decision:"block", reason:$r}'
  exit 0
fi

# clean of criticals → stamp so we don't re-review identical content
echo "$hash" > "$stamp"

adv="$(printf '%s' "$verdict" | jq -c '.advisory // []' 2>/dev/null)"
nadv="$(printf '%s' "$adv" | jq 'length' 2>/dev/null || echo 0)"
if [ "${nadv:-0}" -gt 0 ]; then
  body="$(printf '%s' "$adv" | jq -r '.[] | "  \(.file):\(.line) [\(.rule)] \(.why)"' 2>/dev/null | head -20)"
  jq -n --arg m "gdscript-reviewer advisory (non-blocking):"$'\n'"$body" '{systemMessage:$m}'
fi
exit 0
