# git integration — the commit-path gate

`hooks/pre-commit` runs the deterministic GDScript gates over the **staged**
`.gd` files and aborts the commit on a blocking finding.

It is the backstop for [`../claude-code/gd-check.sh`](../claude-code/README.md).
That hook fires on Claude Code's `Edit`/`Write`, so it never sees code written
in the Godot editor, by another agent or editor plugin, or while the hook itself
was broken or disabled. Everything reaches the index eventually, so that is
where the gate that cannot be walked around belongs.

## Install

```bash
integrations/git/install.sh /path/to/your/godot/repo     # one repo
integrations/git/install.sh --global                     # every repo on the machine
integrations/git/install.sh --uninstall /path/to/repo    # undo
```

The installer sets `core.hooksPath` to `integrations/git/hooks` in this
checkout, so every repo runs the same hook file and an update here reaches all
of them at once — no copies to re-sync.

`core.hooksPath` **replaces** `.git/hooks` wholesale: a repo's own hooks stop
running the moment it is set. The installer refuses a repo that already has its
own hooks, or an existing `core.hooksPath`, unless you pass `--force`.

The hook exits immediately when no `.gd` file is staged, so `--global` is safe
for non-Godot repos — at the cost of shadowing their hooks.

Do not install it in **this** repo: `tests/fixtures/*.gd` violate rules on
purpose, and the gate would block every commit that touches one.

## What it checks

| Gate | Tool | Blocking |
|---|---|---|
| Formatting | `gdscript-formatter --check` | yes |
| Generic lint | `gdscript-formatter lint` | yes |
| Rule corpus | `gd-lint.py` | blocking findings yes, `[advisory]` no |

`gd-lint.py` is found via `$GDLINT`, else beside the hook in this checkout, else
`~/.claude/hooks/gd-lint.py`.

Paths the repo carries but does not author — a vendored addon, generated output
— go in `.claude/gdlint-exclude` at the repo root, one glob per line (`#`
comments allowed):

```
addons/gut/*
addons/*/vendor/*
```

There is no default list: `addons/` holds first-party code too, so the repo
declares what it does not own. Without this, dropping in a fresh third-party
addon stages a pile of *new* files, which are enforced in full, and a commit of
somebody else's code fails on rules that were never theirs — the exact shape of
a gate that gets `--no-verify`d.

Project-local formatter exceptions come from `.claude/gdscript-formatter-disable`
at the repo root, the same file `gd-check.sh` reads, so the two gates agree.
`max-line-length` is always disabled, and `private-access` additionally under
`tests/`.

## Three properties worth knowing

**Staged content, not the working tree.** `git add -p` splits a file; what gets
committed is the index version, so the gates run against blobs read out of the
index. A dirty working tree cannot smuggle a violation past the gate, and cannot
fail a commit that does not contain it.

**Diff-aware**, same contract as `gd-check.sh`: on a file already tracked at
`HEAD`, findings are filtered to the lines the commit changes. Pre-existing
violations on untouched lines do not block — you own what you touch. New files
and the no-`HEAD` case are enforced in full. The authoritative whole-tree run
belongs in CI: a gate that blocks a one-line fix to a legacy file gets bypassed
with `--no-verify`, and then gates nothing at all.

**Fails closed**, unlike `gd-check.sh`. A missing tool aborts the commit and
names the tool. An absent linter is installable, and a gate nobody can tell is
dead is worse than no gate. A *crashed* tool is different: the known
`gdscript-formatter` ternary panic skips that one gate for that one file and
prints a `DEGRADED` warning, so the hole is visible rather than silent.

## What it does not check

The judgment-level corpus — engine-bug lifecycle, DOD `D1`-`D11`, architecture —
has no linter, and the type tier (`godot --check-only`) needs project context
this hook does not set up. Those stay with the `gdscript-reviewer` subagent and
the `Stop` hooks. This gate is the deterministic floor, not the whole review.

## Tests

```bash
bash tests/test_pre_commit.sh                    # stubbed formatter, runs anywhere
REAL_FORMATTER=1 bash tests/test_pre_commit.sh   # also assert the real format gate
```
