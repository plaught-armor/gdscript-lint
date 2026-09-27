#!/usr/bin/env bash
# Point a repository (or all of them) at this package's git hooks.
#
#   install.sh [repo ...]      set core.hooksPath in each repo (default: cwd)
#   install.sh --global        set it in ~/.gitconfig for every repo
#   install.sh --uninstall ... undo the above
#
# core.hooksPath REPLACES .git/hooks wholesale — a repo's own hooks stop running
# the moment it is set. The installer refuses a repo that has its own hooks
# unless --force is given, rather than silently disabling them.

set -u

hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/hooks" && pwd -P)" || {
  echo "install.sh: cannot resolve hooks/ next to this script" >&2; exit 1; }

scope="repo"
uninstall=0
force=0
repos=()
for arg in "$@"; do
  case "$arg" in
    --global)    scope="global" ;;
    --uninstall) uninstall=1 ;;
    --force)     force=1 ;;
    -h|--help)   sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    -*)          echo "install.sh: unknown flag $arg" >&2; exit 1 ;;
    *)           repos+=("$arg") ;;
  esac
done

if [ "$scope" = "global" ]; then
  if [ "$uninstall" = 1 ]; then
    git config --global --unset core.hooksPath 2>/dev/null
    echo "global core.hooksPath unset"
  else
    git config --global core.hooksPath "$hooks_dir"
    echo "global core.hooksPath -> $hooks_dir"
    echo "note: this shadows every repository's own .git/hooks on this machine."
  fi
  exit 0
fi

[ "${#repos[@]}" -eq 0 ] && repos=(".")

rc=0
for r in "${repos[@]}"; do
  root="$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "SKIP  $r — not a git repository" >&2; rc=1; continue; }

  if [ "$uninstall" = 1 ]; then
    git -C "$root" config --unset core.hooksPath 2>/dev/null
    echo "UNSET $root"
    continue
  fi

  own="$(ls "$root/.git/hooks" 2>/dev/null | grep -v '\.sample$' | tr '\n' ' ')"
  if [ -n "$own" ] && [ "$force" = 0 ]; then
    echo "SKIP  $root — has its own hooks ($own); core.hooksPath would disable them. Re-run with --force." >&2
    rc=1
    continue
  fi

  prev="$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$prev" ] && [ "$prev" != "$hooks_dir" ] && [ "$force" = 0 ]; then
    echo "SKIP  $root — core.hooksPath already set to $prev. Re-run with --force." >&2
    rc=1
    continue
  fi

  git -C "$root" config core.hooksPath "$hooks_dir"
  echo "OK    $root -> $hooks_dir"
done
exit $rc
