# Claude Code integration

Reference hooks that wire `gd-lint` (and an optional Godot type tier + LLM
reviewer) into [Claude Code](https://claude.com/claude-code)'s hook system, so
GDScript is checked automatically as the agent edits. Adapt the paths to your
setup — these are examples, not a turnkey install.

## Hooks

| Hook | Event | What it does |
|---|---|---|
| `gd-check.sh` | `PostToolUse` (`Edit\|Write`) | On a `.gd` write: `gdscript-formatter --check` + `lint`, then `gd-lint.py`. Blocks the edit (`decision:block`) on a blocking finding; advisory findings ride along as a non-blocking note. Fails open if a tool is missing. |
| `gd-analyze-stop.sh` | `Stop` | Runs `godot --check-only` on `.gd` changed this session, inside the file's Godot project, and blocks on type/parse errors the linter can't see. Content-hash deduped, fails open. |
| `gd-review-stop.sh` | `Stop` | Optional. Runs an LLM reviewer (`claude -p`) over changed `.gd`, hard-blocks on CRITICAL findings, advises on the rest. Needs the `claude` CLI. |

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
