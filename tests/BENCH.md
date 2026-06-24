# Loop-idiom benchmark — measure before promoting

The loop rules L1/L2/L3 are **advisory** in gd-lint, not edit-blocking. They came
from a project idiom whose stated rationale was performance. Before promoting any
of them to a hard (blocking) rule, the perf claim has to actually hold — DOD:
measure before optimizing. This file records the measurement.

## Run

```bash
godot --headless --script tests/gd-lint/bench_loop_idiom.gd
```

`bench_loop_idiom.gd`: N = 2,000,000, best-of-7, surrounding work held identical,
result accumulated into a sink so nothing is optimized away.

## Results (Godot 4.8.dev custom build, 3 runs)

| Rule | A | B | ratio A/B | reading |
|---|---|---|---|---|
| L1 | `for i in range(arr.size()): arr[i]` | `for v in arr` | **1.2–1.4×** | direct iteration ~1.3× faster — **claim holds** |
| L2 | `for i in range(hi, lo, -1)` | manual `while` | **0.44–0.46×** | descending `range` ~2.2× **faster** than `while` — idiom **inverted** |
| L3 | `for i: int in range(N)` | `for i: int in N` | **0.89–1.06×** | ~break-even, `range(N)` often faster — **perf claim refuted** |

## Conclusions

- **L1 — justified.** Direct iteration is measurably faster (~1.3×) *and* clearer.
  Stays advisory only because "needs the index" is a real, undetectable exception;
  not because the perf is in doubt.
- **L2 — idiom inverted by the data.** The original memory said "descending → `while`".
  Measurement says the opposite: a descending `range(hi, lo, -1)` is ~2.2× FASTER than
  the hand-written `while`. So L2 now flags the slow shape — a **manual descending
  `while` counter** (numeric guard + literal decrement) — and recommends the descending
  `range`. Stays advisory: a `while` whose termination is a *condition* (not a fixed
  count) is legitimate, and the detector can't always tell, so it only fires on the
  clear numeric-countdown shape (`while v >= N: ... v -= K`). Value-drains
  (`while health > 0: health -= damage`) are deliberately not matched.
- **L3 — perf rationale is false.** `for i: int in N` is not faster than
  `for i: int in range(N)` (break-even, sometimes slower). C14 (`range()` returns an
  untyped `Array`) is a **typing** problem — it bites `var x: Array[int] = range(n)`,
  not a typed `for` loop. Kept advisory as a typing/idiom-consistency note, not a perf
  rule; do NOT promote to blocking.

## Candidate-rule speed test (bench_candidate_rules.gd)

Before adding the C3/C14/C9/P22/S11/H13 batch, every perf claim was measured
(N=2M, best-of-5, Godot 4.8.dev, 4 runs):

| Rule | A vs B | ratio | reading |
|---|---|---|---|
| P22 | `clamp/abs/max` vs `clampf/absf/maxf` | **1.26–1.33×** | typed math ~1.3× faster — **perf holds** |
| H13 | `obj.call(&"m")` vs direct `obj.m()` | **1.19–1.21×** | direct ~1.2× faster — modest |
| C3/C14 | iterate untyped `Array` vs typed `Array[int]` | **0.93–0.97×** | wash — **no perf win** |
| S11 | `print()` cost | **0.68 µs/call** | real but tiny — hot-loop-only |
| C9 | (method collision) | n/a | correctness, not benchable |

Decision from the data:
- **C3, C14, C9 → blocking CORRECT rules.** The speed test confirmed they are
  *not* about speed (iteration is a wash); they prevent wrong types (#72566,
  #110659) and method collisions. Same tier as C1, exact-shape, ~0 FP.
- **P22 → advisory PERF.** 1.3× is real, but the typed variant depends on arg
  type (`clamp(int…)` wants `clampi`) — the linter can't tell float from int, so
  it advises, never blocks.
- **H13, S11 → held.** Modest/marginal perf + real FP surface (legit reflection;
  can't detect a gated print).

## Promotion criterion

Move a rule out of `ADVISORY` (in `hooks/gd-lint.py`) to blocking only when:
1. a realistic hot-loop benchmark here shows a consistent ≥1.3× win, AND
2. the rule's false-positive rate on real code is near zero.

On current data only **L1** meets (1); it stays advisory on (2). L2/L3 meet neither —
they remain advisory, style-only.
