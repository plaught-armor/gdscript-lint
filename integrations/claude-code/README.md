# Claude Code integration

Reference hooks that wire `gd-lint` (and an optional Godot type tier + LLM
reviewer) into [Claude Code](https://claude.com/claude-code)'s hook system, so
GDScript is checked automatically as the agent edits. Adapt the paths to your
setup — these are examples, not a turnkey install.

## Hooks

| Hook | Event | What it does |
|---|---|---|
| `gd-check.sh` | `PostToolUse` (`Edit\|Write`) | On a `.gd` write: `gdscript-formatter --check` + `lint`, then `gd-lint.py`. Blocks the edit (`decision:block`) on a blocking finding; advisory findings ride along as a non-blocking note. **Diff-aware** — see below. Fails open if a tool is missing or the formatter panics. |
| `gd-analyze-stop.sh` | `Stop` | Runs `godot --check-only` on `.gd` changed this session, inside the file's Godot project, and blocks on type/parse errors the linter can't see. Content-hash deduped, fails open. |
| `gd-review-stop.sh` | `Stop` | Optional. Runs an LLM reviewer (`claude -p`) over changed `.gd`, hard-blocks on CRITICAL findings, advises on the rest. Needs the `claude` CLI. |

## Diff-awareness (`gd-check.sh`)

You own what you touch. For a file already tracked at `HEAD`, findings are
filtered to the lines this edit actually changed (working tree vs `HEAD`) —
pre-existing violations on untouched lines don't block. Formatting is judged the
same way: it only fails when the file is unformatted *now* and was formatted at
`HEAD`, so an already-dirty file is grandfathered instead of demanding a
whole-file reformat to land a one-line fix.

Full enforcement still applies to new / untracked files, and to every file when
the directory isn't a git repo or the repo has no commits yet. Keep a full-file
run (CI, or `gd-lint.py` over the tree) as the authoritative gate — this hook is
the fast edit-time layer, not the whole story.

**Project-local lint exceptions.** `gdscript-formatter` has no config file, so
the hook reads one: `.claude/gdscript-formatter-disable` at the repo root, one
rule name per line (`#` comments allowed). Use it for rules that clash with a
deliberate, documented convention of that codebase (protocol-mirrored names,
codegen-emitted identifiers, a `_`-prefix privacy convention). `max-line-length`
is always disabled — `--check` already enforces style-guide wrapping, and what's
left is usually an unwrappable string or `res://` path. `private-access` is
additionally disabled under `tests/`, where white-box tests legitimately reach
internals.

## Setup

1. Make `gd-lint.py` reachable. Either symlink it to the Claude Code convention:
   ```bash
   ln -s "$PWD/gd-lint.py" ~/.claude/hooks/gd-lint.py
   ```
   or set `GDLINT=/path/to/gd-lint.py` in the hook's environment.
2. Point the analyzer at your Godot binary: `GODOT_BIN=/path/to/godot` (else it
   uses `godot` on `PATH`; absent → that hook skips).
3. Copy the hook scripts somewhere stable (e.g. `~/.claude/hooks/`) and register
   them in `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         { "matcher": "Edit|Write",
           "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/gd-check.sh\"", "timeout": 30 }] }
       ],
       "Stop": [
         { "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/gd-analyze-stop.sh\"", "timeout": 120 }] },
         { "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/gd-review-stop.sh\"", "timeout": 180 }] }
       ]
     }
   }
   ```
4. Restart Claude Code — hooks load at session start.

## Environment

| Var | Default | Used by |
|---|---|---|
| `GDLINT` | `~/.claude/hooks/gd-lint.py` | `gd-check.sh` |
| `GODOT_BIN` | `godot` on `PATH` | `gd-analyze-stop.sh` |

All three fail open: a missing tool disables that check, it never wedges the
session.
