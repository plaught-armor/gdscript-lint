# Part III — Performance, measured

GDScript is interpreted. Big-O still matters, but the dominating cost in hot
paths is usually the **constant**: Variant boxing, dispatch machinery, property
lookups, bytecode per operation. This part measures those constants.

Every table notes the Godot version it was run on — the engine's interpreter
changes, so a number from 4.7 isn't a promise about 4.9. Reproduce with the bench
scripts in [`../tests/`](../tests/).

> **Before you optimize anything here:** check whether it's in a measured hot
> loop. `(cost per call ns) × (calls per second)` vs `16,600,000 ns` (one 60fps
> frame). Under ~10,000 ns of the frame? The dispatch cost is irrelevant — find a
> different bottleneck.

---

## 1. Dispatch — `match` vs `if/elif` vs a Callable table

Branching on the value of one discriminator (a type code, enum, tag) is the most
common dispatch in gameplay code. The conventional choices are `match`, an
`if/elif` chain, or an `Array[Callable]` "jump table." Measured
(`bench_dispatch_mechanism.gd`, 600k rows, best-of-7, Godot 4.7; baseline =
`Array[Callable]` index = 1.00×):

| Construct | vs Callable table |
|---|---|
| `Array[Callable]` index | 1.00× |
| `match` + direct call | **0.83×** — *slower* than the Callable it would replace |
| `if/elif` + direct call | 1.00× |
| `if/elif` + inline body (no call) | **1.44×** |
| `match`, 6 arms, hit the last | **0.62×** |
| `if/elif`, 6 arms, hit the last | 1.30× |

Two findings most people get wrong:

1. **There is no cheap "jump table" in interpreted GDScript.** `Array[Callable]`
   indexing isn't O(1)-free, and `match` is *worse* than it.
2. **A value-only `match` is the slowest option.** Each arm carries
   pattern-matching machinery (type test, destructure, bind) even when you use
   none of it — ~10 VM opcodes per arm vs ~2 for an `if` branch, and it degrades
   linearly as the matched arm moves later.

**Use `if/elif` for value dispatch**, and inline the arm body when you can — that
inlining is where the 1.44× lives. Reserve `match` for *actual* pattern matching
(binding `var n`, destructuring `[a, b]` / `{"k": v}`, type patterns), where the
expressiveness is the point. → lint rule **D7b**.

---

## 2. Call overhead & indirection

Every layer between the call site and the code costs. Measured (1M iters × 3,
Godot 4.7-beta; baseline = a hand-inlined expression = 1.00×):

| Path | × inline |
|---|---|
| inlined expression | 1.00 |
| `static func` on a `class_name`'d RefCounted | ~2.27 |
| autoload global identifier (`Bus.method()`) | ~2.43 |
| instance method on a cached ref | ~2.67 |
| `get_node(^"X").method()` per call | ~4.06 |
| `signal.emit()`, 1 listener | ~4.5 |
| `signal.emit()`, 4 listeners | ~5.8–11.6 |

Takeaways:

- **Cache node refs.** `get_node()` per call is ~1.7× worse than a cached
  reference — `@onready` it once. → lint rule **(P3, reviewer)**.
- **A stateless helper belongs on a `class_name`'d RefCounted as a `static func`**
  (~2.27×), not as an autoload (~2.43×) or an instantiated object (~2.67×).
- **Signals decouple; they do not speed.** Emitting to even one listener is ~2×
  a static call and scales with listener count. In a hot path with a small, known
  set of consumers, call directly. Emitting a signal every `_physics_process` to
  one known listener is a 2–5× perf bug dressed as architecture. → **P18**.

---

## 3. Loops — three idioms, two of them folklore

Measured `bench_loop_idiom.gd`, N = 2,000,000, best-of-5, **Godot 4.8.dev**:

| Idiom | A | B | A/B | verdict |
|---|---|---|---|---|
| index vs direct | `for i in range(arr.size()): arr[i]` | `for v in arr` | **1.2–1.4×** | direct iteration is faster — **true** |
| descending | `for i in range(hi, lo, -1)` | manual `while` | **0.44–0.46×** | the `while` is ~2.2× **slower** — folklore **inverted** |
| count | `for i: int in range(N)` | `for i: int in N` | **0.89–1.06×** | break-even — **no win** |

- **Iterate directly, not by index.** `for v in arr` is ~1.3× faster than
  `range(arr.size())` plus subscripting — and clearer. Use a `range` index only
  when you actually need `i`. → **L1**.
- **Descending loops: use `range(hi, lo, -1)`, not a hand `while`.** The common
  "descending → while" advice is backwards: the `range` is ~2.2× *faster*. → **L2**.
- **`for i: int in N` is not faster than `range(N)`.** It reads as an idiom, not a
  speedup — they're break-even. The real `range()` problem (C14) is a *typing*
  bug, not a loop-speed one: `var x: Array[int] = range(n)` produces an untyped
  array. That bites assignment, not iteration. → **L3 / C14**.

---

## 4. Typed math functions

The `*f`/`*i` variants (`clampf`, `absf`, `maxf`, `clampi`, …) skip Variant
dispatch. Measured (`bench_candidate_rules.gd`, N = 2M, best-of-5, Godot 4.8.dev):

| | untyped `clamp/abs/max` | typed `clampf/absf/maxf` | ratio |
|---|---|---|---|
| float args | 143,586 µs | 110,523 µs | **~1.30×** |

Real, ~1.3× in a tight float loop — but the typed variant depends on the argument
type: `clamp(i, 0, 9)` on ints wants `clampi`, not `clampf`. A purely syntactic
linter can't always tell, so this is **advisory**. Hard rule in
`_process`/`_physics_process`/`_draw`. → **P22**.

---

## 5. Static typing & the things that are *not* faster

Static typing itself is the biggest single win — typed instructions run ~40–47%
faster than Variant-dispatched ones, which is why `:=` and untyped `for` are
blocking rules (**H1**, **H2**). But two widely-assumed wins don't hold:

| Claim | Measured (Godot 4.8.dev) | Reality |
|---|---|---|
| `obj.method()` beats `obj.call(&"method")` | 1.19–1.21× | true, but modest — the real case against `call()` is **correctness** (typo → silent no-op), not speed → **H13** |
| iterating `Array[int]` beats untyped `Array` | 0.93–0.97× | a **wash** — typed iteration isn't faster here. The case for typed `.filter()`/`.map()` (**C3**) and typed `range()` (**C14**) is *correctness* (the result is silently untyped, #72566 / #110659), not performance |

This is the discipline the whole project runs on: a rule earns "blocking" only
when the data backs it. C3/C9/C14 are blocking because they're **correctness**
bugs; the perf-motivated rules that didn't measure up (L1/L2/L3/P22) are
**advisory**.

---

## The folklore, overturned

If you take three things from this part:

1. **A value-only `match` is the *slowest* dispatch**, not a clean one — use
   `if/elif`.
2. **Descending `while` loops are ~2× slower than a descending `range`** — the
   common advice is backwards.
3. **"Typed is always faster" is false in detail** — `for i: int in N` and typed
   array iteration are break-even; the reasons to write them are *correctness* and
   typing, not speed.

Measure before you optimize. Several "obvious" rules in this project were demoted
to advisory — or inverted — the moment they met a benchmark.
