#!/usr/bin/env bash
# Behavior suite for integrations/git/hooks/pre-commit.
#
# Each case builds a throwaway git repo, stages something, runs the hook and
# asserts its exit status plus (where it matters) what it said. The gates the
# hook delegates to gdscript-formatter are stubbed by default — this package
# owns gd-lint and the hook's own logic (staged-content reading, diff-awareness,
# fail-closed), not the formatter — so the suite runs anywhere, including CI
# with no formatter installed. Set REAL_FORMATTER=1 to additionally assert the
# format gate against the real binary when it is present.
#
# Exit: 0 all cases pass, 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../integrations/git/hooks/pre-commit"
GDLINT="$SCRIPT_DIR/../gd-lint.py"

[ -f "$HOOK" ]   || { echo "FATAL: hook not found at $HOOK" >&2; exit 1; }
[ -f "$GDLINT" ] || { echo "FATAL: gd-lint.py not found at $GDLINT" >&2; exit 1; }

pass=0
fail=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# --- stub formatter: always clean, so cases isolate the hook's own behavior ---
stub_bin="$sandbox/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gdscript-formatter" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/gdscript-formatter"

CLEAN=$'extends Node\n\n\nfunc demo() -> void:\n\tvar b: int = 5\n\tprint(b)\n'
DIRTY=$'extends Node\n\n\nfunc demo() -> void:\n\tvar a := 5\n\tprint(a)\n'

new_repo() {
  local d="$sandbox/repo$RANDOM$RANDOM"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  git -C "$d" config commit.gpgsign false
  printf '%s' "$d"
}

# run_hook <repo> [env assignments...] -> sets $out, returns hook's exit status
run_hook() {
  local repo="$1"; shift
  out="$(cd "$repo" && env PATH="$stub_bin:$PATH" GDLINT="$GDLINT" "$@" bash "$HOOK" 2>&1)"
}

# check <name> <expected-status> <actual-status> [substring that must appear in $out]
check() {
  local name="$1" want="$2" got="$3" needle="${4:-}"
  if [ "$want" != "$got" ]; then
    echo "FAIL  $name — expected exit $want, got $got"
    printf '        output: %s\n' "$out"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -q -- "$needle"; then
    echo "FAIL  $name — output missing '$needle'"
    printf '        output: %s\n' "$out"
    fail=$((fail + 1))
    return
  fi
  echo "PASS  $name"
  pass=$((pass + 1))
}

# 1. nothing staged, or nothing GDScript staged -> silent pass
r="$(new_repo)"
printf 'hello\n' > "$r/README.md"
git -C "$r" add README.md
run_hook "$r"; check "no .gd staged -> pass" 0 $?

# 2. new file with a violation -> blocked, cites the rule and the repo path
r="$(new_repo)"
printf '%s' "$DIRTY" > "$r/bad.gd"
git -C "$r" add bad.gd
run_hook "$r"; check "new file, H1 violation -> block" 1 $? "RULE: bad.gd:5: H1"

# 3. new clean file -> pass
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/good.gd"
git -C "$r" add good.gd
run_hook "$r"; check "new clean file -> pass" 0 $? "OK (1 file(s))"

# 4. pre-existing violation on an untouched line is grandfathered
r="$(new_repo)"
printf '%s' "$DIRTY" > "$r/legacy.gd"
git -C "$r" add legacy.gd
git -C "$r" commit -qm init --no-verify
printf '\n\nfunc added() -> void:\n\tprint("clean")\n' >> "$r/legacy.gd"
git -C "$r" add legacy.gd
run_hook "$r"; check "untouched pre-existing violation -> pass" 0 $?

# 5. violation introduced on a changed line of a tracked file -> blocked
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/mod.gd"
git -C "$r" add mod.gd
git -C "$r" commit -qm init --no-verify
printf '\n\nfunc added() -> void:\n\tvar z := 1\n\tprint(z)\n' >> "$r/mod.gd"
git -C "$r" add mod.gd
run_hook "$r"; check "violation on changed line -> block" 1 $? "H1"

# 6a. staged clean + dirty working tree -> pass (the index is what commits)
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/idx.gd"
git -C "$r" add idx.gd
printf '%s' "$DIRTY" > "$r/idx.gd"      # worktree now violates, index does not
run_hook "$r"; check "dirty worktree, clean index -> pass" 0 $?

# 6b. staged violation + clean working tree -> blocked
r="$(new_repo)"
printf '%s' "$DIRTY" > "$r/idx.gd"
git -C "$r" add idx.gd
printf '%s' "$CLEAN" > "$r/idx.gd"      # worktree clean, index violates
run_hook "$r"; check "clean worktree, dirty index -> block" 1 $? "H1"

# 7. missing tool -> fails CLOSED, and says which tool
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/good.gd"
git -C "$r" add good.gd
out="$(cd "$r" && env PATH="$stub_bin:$PATH" GDLINT="$sandbox/nope.py" bash "$HOOK" 2>&1)"
check "missing gd-lint.py -> block" 1 $? "gd-lint.py not found"

# PATH with git + python3 but deliberately no gdscript-formatter.
nofmt="$sandbox/bin-nofmt"
mkdir -p "$nofmt"
for t in bash git python3 grep sed awk paste ls mktemp dirname rm; do
  src="$(command -v "$t" || true)"
  [ -n "$src" ] && ln -sf "$src" "$nofmt/$t"
done
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/good.gd"
git -C "$r" add good.gd
out="$(cd "$r" && env PATH="$nofmt" GDLINT="$GDLINT" bash "$HOOK" 2>&1)"
check "missing formatter -> block" 1 $? "gdscript-formatter not on PATH"

# 8. advisory-only finding -> passes, but is printed
r="$(new_repo)"
printf 'extends Node\n\nvar queue: Array = [1, 2, 3]\n\n\nfunc drain() -> void:\n\tprint(queue.pop_front())\n' > "$r/adv.gd"
git -C "$r" add adv.gd
run_hook "$r"; check "advisory only -> pass, printed" 0 $? "P6"

# 8b. .claude/gdlint-exclude skips declared paths, and only those
r="$(new_repo)"
mkdir -p "$r/.claude" "$r/addons/vendor"
printf 'addons/vendor/*\n# comment\n\n' > "$r/.claude/gdlint-exclude"
printf '%s' "$DIRTY" > "$r/addons/vendor/third_party.gd"
git -C "$r" add -A
run_hook "$r"; check "excluded path -> pass" 0 $? "1 excluded"

printf '%s' "$DIRTY" > "$r/mine.gd"          # same violation, not excluded
git -C "$r" add mine.gd
run_hook "$r"; check "non-excluded path still blocks" 1 $? "RULE: mine.gd"

# 9. deleted file has nothing to lint -> pass
r="$(new_repo)"
printf '%s' "$DIRTY" > "$r/gone.gd"
git -C "$r" add gone.gd
git -C "$r" commit -qm init --no-verify
git -C "$r" rm -q gone.gd
run_hook "$r"; check "staged deletion -> pass" 0 $?

# 10. a crashed formatter degrades loudly instead of blocking or passing silently
mkdir -p "$sandbox/bin-panic"
cat > "$sandbox/bin-panic/gdscript-formatter" <<'PANIC'
#!/usr/bin/env bash
echo "thread 'main' panicked at src/lib.rs:1:1" >&2
exit 101
PANIC
chmod +x "$sandbox/bin-panic/gdscript-formatter"
r="$(new_repo)"
printf '%s' "$CLEAN" > "$r/good.gd"
git -C "$r" add good.gd
out="$(cd "$r" && env PATH="$sandbox/bin-panic:$PATH" GDLINT="$GDLINT" bash "$HOOK" 2>&1)"
check "formatter panic -> pass, DEGRADED warning" 0 $? "DEGRADED"

# 11. optional: the real formatter's format gate
real_fmt="$(command -v gdscript-formatter || true)"
if [ -n "${REAL_FORMATTER:-}" ] && [ -n "$real_fmt" ]; then
  r="$(new_repo)"
  printf 'extends Node\nfunc demo()->void:\n\tprint( 1 )\n' > "$r/unfmt.gd"
  git -C "$r" add unfmt.gd
  out="$(cd "$r" && env GDLINT="$GDLINT" bash "$HOOK" 2>&1)"
  check "real formatter, unformatted new file -> block" 1 $? "FORMAT: not formatted"
else
  echo "note: skipping real-formatter case (set REAL_FORMATTER=1 with gdscript-formatter installed)" >&2
fi

echo "----"
echo "pre-commit cases: $((pass + fail))  pass: $pass  fail: $fail"
[ "$fail" -eq 0 ] || exit 1
