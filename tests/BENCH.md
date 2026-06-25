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

## Redundant cast — H14/H14b (bench_redundant_cast.gd)

Backs Part II H14/H14b: a redundant `as T` adds a Variant round-trip. N=2M,
best-of-7, 2 runs, Godot 4.8.dev (>1 = the redundant cast is slower):

| Case | ratio | reading |
|---|---|---|
| `(v as Foo).x` vs narrowed `v.x` (inside `if v is Foo`) | **1.2–1.4×** | drop the `as` — `is` already narrowed |
| `(d[0] as Foo).x` vs `d[0].x` (typed `Dictionary[int, Foo]`) | **1.2–1.6×** | typed container already returns `Foo` |

Modest but real in a hot loop, and free to fix (the cast is pure clutter).

## Param/signal typing — H4/H10b (bench_param_types.gd)

Backs Part II H4 (typed signal params) and H10b (type the container param). N=1M,
best-of-7, 2 runs, Godot 4.8.dev:

| Case | ratio (untyped / typed) | reading |
|---|---|---|
| typed vs untyped signal **param** (H4) | **~1.00×** | wash — emit cost dwarfs it; type for the contract (#110573), not speed |
| typed vs untyped Dict **param** (H10b) | **~1.00×** | wash at this scale — type for the honest signature, not speed |

Both are **correctness/contract** rules, not perf rules — they belong in the same
"not actually faster" bucket as Part III §5's H13/C3-C14 (the probing *body* in
H10b would cost more, but a clean typed-vs-untyped param is even).

## Batched tick / process centralization — D8 (bench_process_centralization_proj/)

Backs Part IV D8 — and **corrects** the earlier claim. The question: is it faster
to centralize per-frame work into one (or a few) systems than to let N nodes each
run their own `_physics_process`? Four layouts, swept over entity count N and
per-entity work W (W=0 isolates pure dispatch; W=30 is realistic light work).
Godot 4.8.dev, ~80 physics frames/trial, **independent trials, ordering-bias-
controlled** (per-node measured *last*, so a warming CPU disadvantages it — yet it
still wins; the manager-of-nodes verdict is therefore not an ordering artifact):

baseline = per-node `_physics_process` = 1.00× (higher = faster than per-node):

| Layout | W=0 (pure dispatch) | W=30 (light work) |
|---|---|---|
| per-node `_physics_process` | 1.00× | 1.00× |
| one manager loops `Array[Ent]` calling `e.tick()` | **0.46–0.48×** | 0.47–0.50× |
| four managers, each loops N/4 | 0.46–0.48× | 0.50–0.52× |
| **inline manager** — flat `PackedInt32Array`, no per-entity calls | **2.2–2.3×** | 1.04–1.15× |

Three findings, stable across runs at N ∈ {1000, 10000}:

1. **A manager that loops nodes calling `e.tick()` is ~2× SLOWER than per-node.**
   A GDScript per-entity method call (`e.tick()`, the ~5.3×-inline instance-method
   tier in §2's ladder) costs *more* than the engine's native `_physics_process`
   dispatch. You still pay N calls either way — and the loop adds array iteration
   on top. Centralizing the *call* buys nothing; it loses.
2. **The win requires eliminating the per-entity call.** The inline manager owns a
   flat array and works it in place — there are **no N method calls at all**, just
   array math. That's 2.2–2.3× faster than per-node when work is light (dispatch is
   the whole cost), shrinking toward parity as per-entity work grows and dominates.
3. **"One" vs "a few" systems: no difference.** Four managers ≈ one manager.

**Correction to the prior recording.** An earlier toggle-in-one-scene repro
(`repro_batch_tick_proj/`) reported the manager-of-nodes form as a slight *win*
(1.07–1.19×). That harness measured the per-node phase first and the manager phase
second on the same long-lived nodes — an A/B ordering bias (CPU warms over a run →
the later phase looks faster) compounded by the measuring node *being* the manager.
The trial-isolated bench here removes both confounds and reverses the verdict.
Neither harness supports "manager-of-nodes is faster"; the robust, defensible
conclusion is: **per-entity method dispatch is not cheaper in a loop — the manager
earns its keep by doing *less* (existence-based skipping of dead/distant entities,
lower tick rate) or by going full SoA (flat data, no per-entity calls), not by
replacing N callbacks with N method calls.**

## Removing dead entities — cull strategies (bench_dead_removal.gd)

Companion to P6: how to remove the *dead subset* from a manager-owned array each
frame. Four strategies, swept over N and death fraction; "dead" is intrinsic to
the value so all remove the same set from a fresh copy. µs to cull one pass,
best-of-9, 4.8.dev:

| N | dead % | swap-back | compact (write-cursor) | rebuild | remove_at per dead |
|---|---|---|---|---|---|
| 10,000 | 50% | 485 | **284** | 250 | **1,079** |
| 10,000 | 5% | 348 | **329** | 289 | 411 |
| 1,000 | 50% | 47 | **28** | 24 | 43 |

- **Write-cursor `compact` wins** (~1.7× over swap-back at 50% dead) *and* keeps
  order — one forward pass, each element touched once, one resize at the end.
- **Swap-back's O(1) is per *single* removal, not per cull.** Culling a fraction
  re-examines swapped-in elements (often dead → re-swapped) and resizes per
  removal — slower than one compaction pass. (Single-removal-by-index, like the
  combat example's `kill(slot)`, is still correctly swap-back.)
- **`remove_at` per dead is the O(n·k) trap** — ~4× compact at 50% (P6, one
  element in from the front).
- **rebuild** ties compact on time but allocates a second array — prefer the
  in-place write cursor.

Full strategy/decision writeup: [`bible/removing-dead-entities.md`](../bible/removing-dead-entities.md).

## P6 — Array front-removal is O(n), drain loop is O(n²) (bench_pop_front.gd)

Backs rule P6 ([#45455](https://github.com/godotengine/godot/issues/45455)).
`pop_front()` / `pop_at(0)` remove the head, which shifts every remaining element
down one slot. A single call is O(n); a *drain* loop (pop_front until empty) is
O(n²). This bench drains the same N-element array **four** ways and sweeps N so
the blow-up is visible against the 16,666 µs (60fps) frame budget — i.e. it
answers "how large is large?". Godot 4.8.dev, best-of-7, accumulated into a sink.

```bash
godot --headless --script tests/bench_pop_front.gd
```

| N | pop_front drain | pop_back drain | index walk | swap-back drain | front/swap |
|---|---|---|---|---|---|
| 100 | 4 µs | 3 µs | 1 µs | 5 µs | 0.8× |
| 1,000 | 118 µs | 35 µs | 16 µs | 53 µs | 2.2× |
| 10,000 | **9,998 µs** | 341 µs | 156 µs | 520 µs | 19.2× |
| 50,000 | **252,504 µs** | 1,532 µs | 788 µs | 2,565 µs | 98.4× |

Reading: 10×N → ~85× time (1k→10k) and 5×N → ~25× time (10k→50k) — textbook
O(n²) for pop_front. The other three are linear: at 50k, pop_back 1.5 ms, index
walk 0.79 ms, swap-back 2.6 ms — none over one frame, while pop_front is **252 ms
≈ 15 dropped frames**.

**"Large" pinned by the data:**
- < ~1,000 elements, or off the per-frame path → free (sub-0.1 ms). Don't worry.
- A pop_front drain of **~10,000** elements = **~10 ms ≈ 60% of one 60fps frame**;
  **~12–13k empties the whole budget** in a single frame. That's the threshold
  where P6 stops being pedantic.
- The fix is never "a bigger array is fine with pop_back" — it's that pop_back /
  index / swap-back are all O(n) and stay sub-millisecond-ish at 50k, so the
  O(n²) shape is the whole problem, not the size.

**On swap-back** (the [SwapBackArray](/mnt/based_backup/Repos/SwapBackArray)
addon's technique — `SwapBackUtil.remove_at_*` for `Packed*`, `SwapBackArray` for
Node arrays; here inlined as overwrite-slot-with-last + `resize(-1)`):
- It is O(1) *per removal* → O(n) to drain, and ~98× faster than pop_front at 50k.
  (This arm runs on `PackedInt32Array`, the other three on `Array[int]`, so the
  `front/swap` ratio combines the algorithm delta with a smaller Array-vs-Packed
  container delta — the O(n²)-vs-O(n) term dominates by orders of magnitude.)
- For a pure FIFO **drain**, plain `pop_back` is actually cheaper than swap-back
  (swap-back pays a `resize` per op; pop_back is the engine's tail-drop). Don't
  reach for swap-back just to empty an array.
- Swap-back's real niche is the case this drain *understates*: **O(1) removal at
  an arbitrary index** mid-array (yank an inactive entity from a pool by index)
  where order doesn't matter — something neither `pop_back` nor an index walk
  gives you. That's when it beats the O(n) `remove_at(i)` shift, which is the same
  bug as P6 one element in from the front.

Stays **advisory**: the linter can't see the surrounding loop or the array's
runtime length, and a front-dequeue of a few dozen items is genuinely free —
blocking would be noise. The number above is what makes the advice actionable.

## Promotion criterion

Move a rule out of `ADVISORY` (in `hooks/gd-lint.py`) to blocking only when:
1. a realistic hot-loop benchmark here shows a consistent ≥1.3× win, AND
2. the rule's false-positive rate on real code is near zero.

On current data only **L1** meets (1); it stays advisory on (2). L2/L3 meet neither —
they remain advisory, style-only.
