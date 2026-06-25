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

Part IV opens with **"The case for DOD (even in GDScript)"** — a position piece (argues one side, not neutral) on why DOD is the default even where the interpreter mutes the cache win: correctness-by-construction, structural speed that survives Variant boxing, alignment with Godot's own server substrate, and the escalation ladder that lands on DOD anyway.

**Worked example** (the rules composed, runnable + verified): [DOD by example](dod-by-example.md) — one enemy-combat subsystem taken from a fat-`Enemy` strawman to a data-oriented decomposition (D1–D8 + P6 + C2a), backed by `tests/example_dod_combat_proj/` and a literal run on 4.8.dev.

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
