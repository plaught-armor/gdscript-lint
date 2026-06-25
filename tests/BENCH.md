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

## Dispatch & call-overhead (bench_dispatch_mechanism.gd)

Backs Part III §1 (dispatch) + §2 (call overhead) of the bible. Previously the
chapter cited numbers from Godot 4.7 with **no reproducible script**; this bench
re-measures on the build we ship against. N=600k rows, best-of-7, 3 runs, Godot
4.8.dev. Discriminators are read from a pre-filled `PackedInt32Array` so every
variant pays the same key-fetch and the matched arm can't be constant-folded.

```bash
godot --headless --script tests/bench_dispatch_mechanism.gd
```

§1 dispatch (baseline = `Array[Callable]` index = 1.00×, **higher = faster**):

| Construct | vs Callable | reading |
|---|---|---|
| `Array[Callable]` index | 1.00× | baseline |
| `match` + direct call | **0.67×** | slower than the Callable it would replace |
| `if/elif` + direct call | 1.03× | ~par with Callable |
| `if/elif` + inline body | **~2.4×** | the only clear win — inlining beats the table |
| `match`, 6 arms, hit last | **0.41×** | linear scan degrades hard |
| `if/elif`, 6 arms, hit last | 0.78× | degrades too, but ~1.9× faster than `match` |

§2 call overhead (baseline = inline expr = 1.00×, **higher = slower**; trivial
inline baseline → ratios are an upper bound on relative overhead):

| Path | × inline | reading |
|---|---|---|
| inline | 1.00 | baseline (`acc += i + 1`) |
| `static func` on RefCounted | ~4.1× | cheapest indirection |
| instance method, cached ref | ~5.1× | |
| `get_node()` per call | ~9.8× | ~2× a cached ref — cache it |
| `signal.emit()`, 1 listener | ~9.5× | ≈ a `get_node()` call |
| `signal.emit()`, 4 listeners | ~23× | scales ~linearly with listeners |

Findings (vs the old 4.7 figures the chapter used to cite): the qualitative story
is unchanged and **stronger** — `match` is the slowest value-dispatch at every arm
count; inlining an `if/elif` body is the real speed win; signals are not a speed
tool and scale with listener count. Magnitudes shifted (engine version + a more
trivial inline baseline), which is exactly why the chapter is version-tagged.
Not benched here: the autoload-global-identifier path (needs a project with a
registered autoload, not a standalone `--script` run) — carried from the older
ladder, flagged as un-re-measured.

## Static typing, groups, convention dispatch, autoload

Backs the remaining measurable perf claims across Parts II–IV. All Godot 4.8.dev,
best-of-7, 2–3 runs.

**Static typing (`bench_static_typing.gd`, N=2M)** — backs Part III §5 / II §1:

| Pair | ratio | reading |
|---|---|---|
| untyped (Variant) vs fully typed, int arithmetic | **1.33–1.38×** | typed ~25–28% faster — real, but **below the folklore "40–47%"** |
| `:=` inferred vs `var x: T =` explicit | **1.02–1.04×** | **wash** — `:=` is typed; H1 is a consistency rule, not perf |

**Group ops (`bench_group_ops.gd`)** — backs Part IV D2a:

| Call | measured | reading |
|---|---|---|
| `add+remove_from_group` | ~55 ns/pair | O(1), cheap |
| `is_in_group(&"x")` | ~23 ns/call | O(1) |
| `get_first_node_in_group` | ~34 ns/call | O(1), no alloc |
| `is_in_group(&"player")` vs `is Player` | **1.00×** | identical — prefer `is` for *safety*, not speed |
| `get_nodes_in_group` vs cached array | **7.6×** slower | the alloc footgun (group=200; grows with size) |

**Convention dispatch (`bench_convention_dispatch.gd`, N=1M)** — backs Part IV D7a:

| Pair | ratio | reading |
|---|---|---|
| `Id.keys()[id].to_lower()` vs `if/elif` literal helper | **1.95×** | the keys()/to_lower() allocation costs ~2× — helper holds |

**Autoload (`autoload_bench_proj/`, N=600k)** — completes Part III §2's ladder
(needs a real project; autoload globals don't exist under bare `--script`):

| Path | × inline |
|---|---|
| inline | 1.00 |
| static func | ~4.16 |
| instance method | ~5.31 |
| autoload global ident `Bus.x()` | ~5.71 |

Autoload lands just above the instance-method tier and well below `get_node()`
(~9.8× in the dispatch bench) — confirms "use the global ident, don't `get_node()`
an autoload in a hot path."

## Dict access — P9 (bench_dict_access.gd)

Backs Part I's P9 row (#68834, Lua-style `d.key` slower than `d["key"]`, fixed
4.4). N=2M, best-of-7, 2 runs, Godot 4.8.dev:

| Access | ratio (`d.key` / `d["key"]`) | reading |
|---|---|---|
| `d.key` vs `d["key"]` | **1.01×** | gap closed — confirmed fixed |

So the old "use brackets for speed" argument is dead on 4.8.dev; bracket access
remains the style preference for type-clarity (S7), not perf.

## Promotion criterion

Move a rule out of `ADVISORY` (in `hooks/gd-lint.py`) to blocking only when:
1. a realistic hot-loop benchmark here shows a consistent ≥1.3× win, AND
2. the rule's false-positive rate on real code is near zero.

On current data only **L1** meets (1); it stays advisory on (2). L2/L3 meet neither —
they remain advisory, style-only.
