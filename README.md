# gdscript-lint — engine-aware GDScript linting

> **Name is provisional.** `gdlint` is taken by [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit); pick a distinct name before publishing.

A zero-dependency GDScript linter plus the rule corpus behind it. It does **not**
replace `gdformat` / `gdtoolkit` — it catches the **Godot engine gotchas they
don't**: `Packed*Array` traps, typed `.filter()`/`.map()` returning untyped,
native-method collisions, value-only `match` dispatch cost, `StringName`
literals, loop idioms. Every performance claim is **benchmarked before it ships**
(see `BENCH.md`), and each finding is labelled **CORRECT / PERF / STYLE** so you
know whether it's a bug or a preference.

## Why it exists

`gdtoolkit`'s `gdlint` covers generic style (naming, unused, dead code).
`gdformat` (and `gdscript-formatter`) cover formatting. Neither knows the
**engine-specific** failure modes that bite in real Godot 4 projects — the kind
that compile fine and break (or silently corrupt) at runtime. This fills that
gap, with each rule tied to a Godot issue number where one exists.

## Components

| Piece | What |
|---|---|
| `gd-lint.py` | The linter — pure Python stdlib (no pip, no tree-sitter), one file. Masks strings/comments, applies the rules, exits non-zero on a blocking finding. |
| `rules/*.md` | The canonical knowledge — teaching prose + rationale for every rule, with Godot issue links. `index.md` is the map. |
| `tests/` | Per-rule fixtures + a runner that asserts each rule fires exactly where expected, validated against real GDScript the engine accepts. |
| `BENCH.md` | Measured perf data for every perf-motivated rule + the promotion criterion. |

> This repo is the canonical home. The author's Claude Code setup consumes it by
> symlink (`integrations/claude-code/`), so the linter and rules have one source
> of truth and don't drift.

## Rules

Each finding prints `path:line: RULE [CATEGORY]: message`.

| Rule | Cat | Sev | Catches |
|---|---|---|---|
| C1 | CORRECT | block | `const Packed*Array` (reports byte size, reads 0.0 — #88753) |
| C3 | CORRECT | block | typed `Array[T] = coll.filter()/.map()` → untyped (#72566) |
| C9 | CORRECT | block | redefining a reserved Node/Object method (collision) |
| C14 | CORRECT | block | typed `Array[T] = range()` → untyped (#110659) |
| H1 | PERF | block | `:=` instead of explicit `var x: T =` (static typing ~40% faster) |
| H2 | PERF | block | untyped `for x in …` (type the loop var) |
| S6 | PERF | block | `Array[primitive]` where a `Packed*Array` exists |
| D7b | PERF | block | value-only `match` (~5× dispatch vs `if/elif`) |
| P12a | PERF | block | bare string to a `StringName` param (use `&"x"`) |
| S1 | STYLE | block | inline lambda (extract to a named method) |
| S6b | STYLE | block | redundant `Packed*Array()` / `([...])` constructor on a typed assign |
| S15 | STYLE | block | `== ""` / `.size() == 0` instead of `.is_empty()` |
| L1 | PERF | advisory | `range(coll.size())` index loop (iterate directly — measured ~1.3×) |
| L2 | PERF | advisory | manual descending `while` counter (descending `range` is ~2× faster) |
| L3 | STYLE | advisory | `range(N)` count loop (idiom `for i: int in N`; measured break-even) |
| P22 | PERF | advisory | float `clamp/abs/lerp` → `clampf/absf/lerpf` (~1.3×) |

**Blocking** = exit 1 (fail the gate). **Advisory** = printed with `[advisory]`,
exit stays 0 — a non-blocking note. Advisory rules are perf/style preferences
whose measured win is modest or whose detection carries some false-positive risk.

## Install & use

Requires Python 3. No dependencies.

```bash
python3 gd-lint.py path/to/script.gd [more.gd ...]
# exit 1 if any BLOCKING finding, else 0. Advisory findings print but don't fail.
```

Suppress per line or per file:

```gdscript
var x := 5            # gdlint: ignore[H1]      — one rule
var y := 6            # gdlint: ignore          — all rules on this line
# gdlint: disable-file (in the first 5 lines)   — skip the whole file
```

### Pre-commit / CI

```yaml
# .pre-commit-config.yaml
- repo: local
  hooks:
    - id: gdscript-lint
      name: gdscript-lint
      entry: python3 gd-lint.py
      language: system
      files: \.gd$
```

## The type tier (optional)

`gd-lint.py` is purely syntactic by design — it never tries to infer types.
For type-aware checks (type mismatch, can't-infer, native-method override,
unknown member) the right tool is **Godot's own analyzer**, not a hand-built
type system:

```bash
godot --headless --path <project> --check-only --script res://path.gd
```

Run inside the project so `class_name`/autoload/cross-script types resolve. This
is the authoritative type checker; wiring its output into a gate gives you the
type layer for free. (The source repo ships a hook that does exactly this.)

## Measure before you enforce

Perf rules are only added once a benchmark shows the win is real. `BENCH.md`
records the methodology + numbers. This discipline has already **flipped one
rule** (L2 — the data showed a descending `range` beats the hand `while`, the
opposite of the original idiom) and **demoted three** to advisory (L1/L3/P22 —
modest or break-even). A rule graduates from advisory to blocking only on a
measured ≥1.3× win with a near-zero false-positive rate.

## Tests

```bash
bash tests/run.sh                 # parse-validate fixtures with Godot + assert findings
SKIP_GODOT=1 bash tests/run.sh    # skip the Godot pass (faster)
GODOT_BIN=/path/to/godot bash tests/run.sh
```

Fixtures mark the lines that must flag with `# EXPECT <RULE>`; unmarked lines are
negatives, so a false positive fails the run. To add a rule, drop a fixture and
the runner auto-discovers it.

## License

MIT — see `LICENSE`.
