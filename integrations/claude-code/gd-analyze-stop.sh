#!/usr/bin/env bash
# Stop hook — Godot analyzer tier. The type-aware complement to gd-lint (which
# is syntactic / stdlib). Runs `godot --check-only` on every .gd changed this
# session, INSIDE its Godot project so class_name + autoload + cross-script
# types resolve, and blocks on the hard type/parse errors the regex linter
# cannot see (type mismatch, can't-infer, native-method override, unknown
# member). This is the "we already have a real parser — it's Godot" tier; no
# fork, no hand-built type inference.
#
# Cost: ~1.5s per changed .gd, so it is content-hash deduped (idle turns free)
# and runs at Stop, not per-edit. Fails OPEN on any tooling gap.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
GODOT_BIN="${GODOT_BIN:-$(command -v godot 2>/dev/null || echo godot)}"
command -v "$GODOT_BIN" >/dev/null 2>&1 || [ -x "$GODOT_BIN" ] || exit 0

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" 2>/dev/null || exit 0

changed="$(
  {
    git diff --name-only -- '*.gd'
    git diff --name-only --cached -- '*.gd'
    git ls-files --others --exclude-standard -- '*.gd'
  } 2>/dev/null | sort -u | head -30
)"
[ -z "$changed" ] && exit 0

stamp="$(git rev-parse --git-dir 2>/dev/null)/gd-analyze-stamp"
hash="$(printf '%s\n' "$changed" | xargs -r cat 2>/dev/null | sha1sum | cut -d' ' -f1)"
[ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ] && exit 0

# walk up from a file's dir to the nearest project.godot
_find_project() {
  local dir; dir="$(cd "$(dirname "$1")" && pwd -P)"
  local guard=0
  while [ "$dir" != "/" ] && [ "$guard" -lt 40 ]; do
    [ -f "$dir/project.godot" ] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
    guard=$((guard + 1))
  done
  return 1
}

# True if any dir between the file and the project root holds a .gdignore.
# Godot skips such dirs entirely (no import, no class_name registration), so a
# per-file --check-only there can never resolve sibling class_name types and
# will emit guaranteed-false "Could not find type" errors (e.g. golden/fixture
# output committed as reference text). Honor the same ignore the engine does.
_gdignored() {
  local dir; dir="$(cd "$(dirname "$1")" && pwd -P)"
  local stop="$2"
  local guard=0
  while [ "$dir" != "/" ] && [ "$guard" -lt 40 ]; do
    [ -f "$dir/.gdignore" ] && return 0
    [ "$dir" = "$stop" ] && break
    dir="$(dirname "$dir")"
    guard=$((guard + 1))
  done
  return 1
}

errors=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  proj="$(_find_project "$root/$f")" || continue        # not in a Godot project
  _gdignored "$root/$f" "$proj" && continue             # dir Godot itself skips
  abs="$(cd "$(dirname "$root/$f")" && pwd -P)/$(basename "$f")"
  rel="res://${abs#"$proj"/}"
  out="$("$GODOT_BIN" --headless --path "$proj" --check-only --script "$rel" 2>&1)"
  parsed="$(printf '%s\n' "$out" | awk -v fn="$f" '
    /SCRIPT ERROR: Parse Error:/ { m=$0; sub(/.*Parse Error: /,"",m); have=1; next }
    have && /at: .*:[0-9]+\)/    { l=$0; sub(/.*:/,"",l); sub(/\).*/,"",l); print "  " fn ":" l ": " m; have=0 }
  ')"
  if [ -n "$parsed" ]; then
    errors="${errors}${errors:+$'\n'}${parsed}"
  fi
done <<< "$changed"

if [ -n "$errors" ]; then
  # do NOT stamp — keep blocking until the type errors are fixed (content change)
  jq -n --arg r "Godot analyzer: type/parse error(s) — fix before stopping:"$'\n'"$errors" \
    '{decision:"block", reason:$r}'
  exit 0
fi

echo "$hash" > "$stamp"          # clean → stamp so identical content isn't re-checked
exit 0
