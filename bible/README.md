# The GDScript Bible

*Godot 4 GDScript: gotchas & performance, measured.*

Most GDScript advice is folklore — repeated, rarely measured, often stale by a
Godot version or two. This is the opposite: every engine bug links to its issue
and its fix-version; every performance claim is **benchmarked, with the numbers
and a reproducible script**; and where measurement contradicts the common wisdom,
it says so plainly.

It's the long-form companion to the [`gd-lint`](../) rules. The rules are terse
flag conditions; this is the *why* — full symptoms, repros, fixes, and data.

## Contents

| Part | Covers | Status |
|---|---|---|
| [01 — Engine bugs](01-engine-bugs.md) | crashes / leaks / silent corruption, each with issue # + version status | drafted |
| [02 — Type system & async](02-type-async.md) | static typing, lambdas, `await`/coroutine traps, signal lifetimes | drafted |
| [**03 — Performance, measured**](03-performance.md) | **dispatch, loops, math, signals — benchmarked, with the wisdom it overturns** | **drafted** |
| [04 — Data-oriented design](04-data-oriented.md) | existence-based processing, ID refs, hot/cold split, condition tables | drafted |
| [05 — Architecture](05-architecture.md) | project skeleton, autoloads, naming, subsystem shapes | drafted |
| [06 — Resource loading](06-resource-loading.md) | preload/load/threaded, cache modes, UID files | drafted |
| [07 — Architecture types](07-arch-types.md) | scene-tree composition vs DOD vs ECS, comp-vs-inheritance, the escalation ladder — when/why each, sourced | drafted |
| [**08 — Persistence**](08-persistence.md) | **save/load — Object-deserialization RCE, compression measured (binary+zstd beats compact wire formats), atomic write, migration** | **drafted** |

Part IV opens with **"The case for DOD (even in GDScript)"** — a position piece (argues one side, not neutral) on why DOD is the default even where the interpreter mutes the cache win: correctness-by-construction, structural speed that survives Variant boxing, alignment with Godot's own server substrate, and the escalation ladder that lands on DOD anyway.

## Worked examples

The rules composed, runnable + verified. Each carries a researched "variants & use-cases" section. Backed by `tests/example_dod_*_proj/` and literal runs on 4.8.dev. Files prefixed `ex-`, filed under the chapter folder they support (`04-data-oriented/`; save/load in `08-persistence/`).

| Example | Covers |
|---|---|
| [combat](04-data-oriented/ex-combat.md) | enemy-combat subsystem, fat-`Enemy` strawman → data-oriented decomposition (D1–D8 + P6 + C2a) |
| [perception](04-data-oriented/ex-perception.md) | existence-based alert state + the corrected D8 (inline SoA, do-less) |
| [membership](04-data-oriented/ex-membership.md) | D2b — owner-held `Array` vs tree-global `&"alive"` group; ration groups like autoloads |
| [inventory](04-data-oriented/ex-inventory.md) | D11, one registry table with convention-derived assets, no mirror arrays |
| [object pool](04-data-oriented/ex-pool.md) | P21 free-list + slot reuse, no per-frame alloc |
| [spatial hash](04-data-oriented/ex-spatial.md) | cell→occupants neighbor queries that touch a constant few cells |
| [save/load](08-persistence/ex-save.md) | relational POD record, ids not objects, with the binary-vs-JSON security boundary |
| [stat/upgrade](04-data-oriented/ex-upgrade.md) | modifier-order transform + the authoring-equivalence test (generator vs hand-authored `.tres`, locked equal) |

## Technique notes

Measured single-topic deep-dives. Files prefixed `note-`, filed under the chapter they belong to (`02-type-async/`, `03-performance/`).

| Note | Covers |
|---|---|
| [Removing dead entities](03-performance/note-removing-dead-entities.md) | swap-back vs write-cursor compaction vs the `remove_at` trap; one removal vs mass cull have different best answers (P6 + D2 + D8) |
| [StringName vs String](02-type-async/note-stringname-vs-string.md) | use `StringName` (`&"x"`) for identifiers, `String` for text; measured ~1.2×, but mostly correctness + engine-API contract, not speed (D10 + P12a/P12b) |

## Snippet style (good vs bad)

Every `gdscript` code block — or each segment within a mixed block — opens with a
polarity header comment, and **that header is the only signal** (no prose cues):

| Header | Meaning | Linted? |
|---|---|---|
| `# Good — …` | the recommended shape | ✅ enforced |
| `# Or — …` | a good alternative | ✅ enforced |
| `# Bad — …` | an anti-pattern | ❌ skipped |
| `# Repro — …` | an engine-bug repro | ❌ skipped |
| `# Naive — …` | the strawman before a refactor | ❌ skipped |

An **untagged** block defaults to enforced (must lint clean) — the fail-safe, so
tag only the bad code. `tests/lint_bible_snippets.py` extracts every block, splits
on these headers, and runs `gd-lint.py` on the enforced segments; CI fails if any
trips a rule. That's how the bible's good examples are kept honest to its own rules.

## What makes this worth reading

- **Version-tagged.** Every engine bug says whether it's live, and in which Godot
  version it was fixed — so you don't carry a workaround for a bug that's gone.
- **Measured, not asserted.** Part III is the centerpiece: real timings on a real
  Godot build, best-of-N, with the bench scripts in [`../tests/`](../tests/).
- **Overturns folklore.** Some widely-repeated idioms are *wrong* when you measure
  — descending `while` loops, `for i in N` over `range(N)`, "typed is always
  faster." Part III shows the data.

## Methodology (Part III)

- Timed with `Time.get_ticks_usec()`, best-of-N runs, all surrounding work held
  identical, results accumulated into a sink so nothing is optimized away.
- Each table notes the Godot version it was measured on (the engine changes; old
  numbers are flagged).
- Reproduce: `tests/bench_loop_idiom.gd`, `tests/bench_candidate_rules.gd` — run
  with `godot --headless --script <file>`.
