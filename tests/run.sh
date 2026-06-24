#!/usr/bin/env bash
# gd-lint test suite. For every fixture under fixtures/:
#   1. (optional) parse-validate with the Godot binary (--check-only) so we
#      only ever assert against GDScript the engine actually accepts.
#   2. Assert gd-lint.py's findings EXACTLY match the fixture's inline
#      `# EXPECT <RULE>` markers — every expected finding caught, nothing extra.
#
# A fixture line that should trigger rule R carries a trailing `# EXPECT R`.
# Clean lines (negatives) carry no marker; a false positive there fails the run.
#
# Env:
#   GODOT_BIN   path to the godot binary (default: repo-local 4.x build).
#   SKIP_GODOT  set to 1 to skip the parse-validation pass.
#
# Exit: 0 all fixtures pass, 1 on any mismatch or invalid fixture.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURES="$SCRIPT_DIR/fixtures"
GDLINT="$SCRIPT_DIR/../gd-lint.py"
# Godot binary: $GODOT_BIN, else `godot` on PATH. If absent the parse-validation
# pass is skipped (the rule assertions still run).
GODOT_BIN="${GODOT_BIN:-$(command -v godot 2>/dev/null || echo godot)}"

fail=0
pass=0
total=0

if [ ! -f "$GDLINT" ]; then
  echo "FATAL: gd-lint.py not found at $GDLINT" >&2
  exit 1
fi

# --- one-time parse-validation of every fixture (engine accepts it) ---
godot_ok=0
if [ -z "${SKIP_GODOT:-}" ] && [ -x "$GODOT_BIN" ]; then
  godot_ok=1
  tmp="$(mktemp -d)"
  cp "$FIXTURES"/*.gd "$tmp/"
  for f in "$tmp"/*.gd; do
    name="$(basename "$f")"
    # Some fixtures intentionally contain code the engine rejects (e.g. C9
    # native-method overrides — Godot itself errors on them). Skip those.
    if head -3 "$f" | grep -q 'no-godot-validate'; then
      continue
    fi
    if ! ( cd "$tmp" && "$GODOT_BIN" --headless --check-only --script "$name" ) >/dev/null 2>&1; then
      echo "INVALID FIXTURE (Godot parse error): $name" >&2
      fail=$((fail + 1))
    fi
  done
  rm -rf "$tmp"
else
  echo "note: skipping Godot parse-validation (set GODOT_BIN or unset SKIP_GODOT to enable)" >&2
fi

# --- per-fixture expected-vs-actual ---
norm() { sort -u; }

for fx in "$FIXTURES"/*.gd; do
  name="$(basename "$fx")"
  total=$((total + 1))

  # expected: "<line> <RULE>" from `# EXPECT <RULE> [<RULE>...]` markers
  # (a line may legitimately trip multiple rules — list them space-separated).
  expected="$(
    while IFS= read -r hit; do
      ln="${hit%%:*}"
      rest="${hit#*EXPECT }"
      for tok in $rest; do
        case "$tok" in [A-Za-z0-9]*) echo "$ln $tok" ;; esac
      done
    done < <(grep -nE 'EXPECT[[:space:]]+[A-Za-z0-9]' "$fx" 2>/dev/null) | norm
  )"

  # actual: "<line> <RULE>" from gd-lint output `path:line: RULE [CAT]: msg`
  actual="$(python3 "$GDLINT" "$fx" 2>/dev/null \
    | sed -E 's/^.*:([0-9]+):[[:space:]]+([A-Za-z0-9]+).*/\1 \2/' | norm)"

  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    echo "PASS  $name"
  else
    fail=$((fail + 1))
    echo "FAIL  $name"
    # missing = expected but not produced; extra = produced but not expected
    miss="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed '/^$/d')"
    extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed '/^$/d')"
    [ -n "$miss" ] && printf '        missing (expected, not caught):\n%s\n' "$(printf '%s\n' "$miss" | sed 's/^/          /')"
    [ -n "$extra" ] && printf '        extra (false positive):\n%s\n' "$(printf '%s\n' "$extra" | sed 's/^/          /')"
  fi
done

echo "----"
echo "fixtures: $total  pass: $pass  fail: $fail  godot-validate: $([ "$godot_ok" = 1 ] && echo on || echo off)"
[ "$fail" -eq 0 ] || exit 1
