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

**In plain terms:** speed work only counts where code actually repeats a lot. A
single frame at 60 fps gives you about 16.6 million nanoseconds to do everything;
if a piece of code only eats a few thousand of those, making it faster won't help
the game feel any better. Before tuning anything, do the back-of-envelope math to
check the call is even in the running.

---

## 0. Hot paths and cold paths

**In plain terms:** "hot" means code that runs over and over each second (every
frame, or inside a big loop); "cold" means code that runs once in a while (boot,
loading, a button press). Everything in this chapter is aimed at hot code — for
cold code, prefer the version that's easiest to read.

Everything in this part only matters on a **hot path**. Knowing which of your code
is hot — and which isn't — is the single most important optimization skill,
because it tells you where the numbers below apply and, just as usefully, where
they *don't*.

**A hot path is code that runs many times per frame, or many times per second.**
The usual suspects:

- `_process`, `_physics_process`, `_draw` — called every frame (60+/sec).
- Inner loops over many items — particles, tiles, enemies, pathfinding nodes.
- Per-entity ticks when there are lots of entities.
- Anything called *from inside* one of the above.

**A cold path is code that runs rarely** — once, or in response to a user action:

- `_ready`, `_init`, `_enter_tree` — once per node, at spawn.
- Boot, level load, save/load, scene setup.
- Button presses, menu navigation, dialogue choices.
- Validation and configuration checks.

The frame-budget test makes "hot" precise: one 60 fps frame is `16,600,000 ns`.
Multiply a function's cost per call by how often it runs per second; if the result
is a meaningful slice of that budget, it's hot. If it's a few thousand nanoseconds
of 16.6 million, it's not — and optimizing it is wasted effort that usually costs
you readability. **A `match` that runs once on a button press is fine. The same
`match` in `_physics_process` over 500 enemies is a hot path.**

**Functions are hot or cold by where they're called, not by what they do.** The
exact same helper can be hot when called per-enemy per-frame and cold when called
once at load. So you don't optimize a *function* — you optimize a *call site*.
Profile to find the hot ones; leave the cold ones readable. (This is why the lint
rules that didn't measure up are *advisory*, not blocking: the linter can't see
whether a given line is on a hot path, so it can't justify forcing the fast shape
everywhere.)

**Data is hot or cold too — and the split is the same idea applied to fields.**
A field is hot if it's read or written every frame, cold if it's set once and
mostly read. For an enemy:

- **Hot:** position, velocity, current health, current AI state — touched every
  tick.
- **Cold:** max health, the damage table, the model path, dialogue strings, sound
  ids — set at load, read occasionally.

Keep the hot fields together on the small per-instance object the hot loop walks,
and move the cold fields out to a single shared resource (one `EnemyDef` referenced
by all enemies of that kind). The hot loop then touches less memory per iteration,
and the cold data lives in one tunable place instead of being copied onto every
instance. The full treatment — with the existence-based and shared-`Def` patterns —
is in [Part IV §5 (hot/cold data split, D5)](04-data-oriented.md). The through-line:
**spend your effort where the work actually repeats, in both code and data.**

---

## 1. Dispatch — `match` vs `if/elif` vs a Callable table

**In plain terms:** when you need to pick between several actions based on the
value of one thing (a kind, a state, a tag), there are three usual ways to write
it. The numbers below say which one is actually fastest in GDScript — and the
common assumption ("`match` is the clean fast one") is wrong.

Branching on the value of one discriminator (a type code, enum, tag) is the most
common dispatch in gameplay code. The conventional choices are `match`, an
`if/elif` chain, or an `Array[Callable]` "jump table." Measured
(`bench_dispatch_mechanism.gd`, 600k rows, best-of-7, 3 runs, **Godot 4.8.dev**;
baseline = `Array[Callable]` index = 1.00×, higher = faster):

| Construct | vs Callable table |
|---|---|
| `Array[Callable]` index | 1.00× |
| `match` + direct call | **0.67×** — *slower* than the Callable it would replace |
| `if/elif` + direct call | 1.03× |
| `if/elif` + inline body (no call) | **~2.4×** |
| `match`, 6 arms, hit the last | **0.41×** |
| `if/elif`, 6 arms, hit the last | 0.78× |

**In plain terms:** higher is faster. The Callable-table row is set to 1.00 so
everything else is a multiplier on it. So `match + call` at 0.67× is running about
two-thirds as fast as the Callable table; `if/elif` with the body inlined at ~2.4×
is more than twice as fast. The 6-arm rows show what happens when the answer is
the *last* arm checked — `match` drops to 0.41× (it slows down a lot as the list
grows), while `if/elif` only drops to 0.78×.

Two findings most people get wrong:

1. **There is no cheap "jump table" in interpreted GDScript.** `Array[Callable]`
   indexing isn't free, and `match` is *worse* than it at every arm count. The
   only construct that clearly beats the Callable table is an `if/elif` chain with
   the **body inlined** (no call) — ~2.4×.
2. **A value-only `match` is the slowest option, and it degrades with arm count.**
   Each arm carries pattern-matching machinery (type test, destructure, bind) even
   when you use none of it, and arms are scanned in order: at 3 arms `match` is
   ~1.5× slower than `if/elif`+call (0.67 vs 1.03); at 6 arms hitting the last,
   ~1.9× slower (0.41 vs 0.78).

**In plain terms:** `match` looks like a clean `switch` from other languages, but
in GDScript it isn't one — it's the *pattern-matching* construct, and every arm
quietly pays for machinery (can this value destructure? bind? is it this type?)
that plain value-branching never needs. An `if/elif` chain skips all of that, and
because the body is right there you can do the work inline instead of calling out
to a function. That "do it right here" is the actual speed-up.

**Use `if/elif` for value dispatch**, and inline the arm body when you can — that
inlining is where the win lives. Reserve `match` for *actual* pattern matching
(binding `var n`, destructuring `[a, b]` / `{"k": v}`, type patterns), where the
expressiveness is the point. → lint rule **D7b**.

---

## 2. Call overhead & indirection

**In plain terms:** every step the engine takes to figure out *which* function to
run is work on top of the function itself. A direct call is cheap; going through
an object, a singleton, a name-lookup, or a list of subscribers all add bookkeeping
on the way in. The table below shows how much each step adds.

Every layer between the call site and the code costs. Measured
(`bench_dispatch_mechanism.gd`, 600k iters, best-of-7, 3 runs, **Godot 4.8.dev**;
baseline = a hand-inlined expression = 1.00×, higher = slower). The inline
baseline is deliberately trivial (`acc += i + 1`), so these ratios are an *upper
bound* on relative overhead — the durable findings are the ordering and the signal
scaling, both stable across runs:

| Path | × inline |
|---|---|
| inlined expression | 1.00 |
| `static func` on a `class_name`'d RefCounted | ~4.1 |
| instance method on a cached ref | ~5.3 |
| autoload global identifier (`Bus.method()`) | ~5.7 |
| `get_node(^"X").method()` per call | ~9.8 |
| `signal.emit()`, 1 listener | ~9.5 |
| `signal.emit()`, 4 listeners | ~23 |

(The autoload row needs a real project with a registered `[autoload]`, so it's
measured separately — `tests/autoload_bench_proj/` — against the same inline
baseline.)

**In plain terms:** in this table higher means *slower* (the opposite of §1's
table) — the inline baseline is 1.00, and ~4.1 means "about four times as long as
just doing the work right there." So a static helper call costs ~4×, an instance
method ~5×, an autoload ~6×, a `get_node()` lookup ~10×, and a signal emit with
four listeners ~23×. Same answer at the end, very different cost to *get* to it.

**In plain terms:** the further the engine has to travel to find the code you want
to run, the more it costs. Inlining the work is free — there's nothing to find. A
`static func` is just a known address. An instance method has to go through an
object; an autoload through a global singleton; a `get_node()` has to *walk the
scene tree by name* every single call; and a signal has to look up everyone who
subscribed and call each of them. Same answer, very different amounts of
bookkeeping.

Takeaways:

- **Cache node refs.** `get_node()` per call is ~2× worse than calling through a
  cached reference (~9.8 vs ~5.3) — `@onready` it once so the lookup happens a
  single time, not every frame. → lint rule **(P3, reviewer)**.
- **A stateless helper belongs on a `class_name`'d RefCounted as a `static func`**
  (~4.1×) — the cheapest indirection here, cheaper than an instance method (~5.3×)
  or an autoload (~5.7×).
- **Signals decouple; they do not speed.** Emitting to even one listener costs
  about as much as a `get_node()` call, and it scales with listener count — four
  listeners is ~2.4× the one-listener cost. The reason to use a signal is that the
  sender doesn't need to know who's listening — that's an architecture win, not a
  speed one. In a hot path with a small, known set of consumers, call directly.
  Emitting a signal every `_physics_process` to one known listener is a perf bug
  dressed as architecture. → **P18**.

---

## 3. Loops — three idioms, two of them folklore

**In plain terms:** three common pieces of loop advice turn out to be wrong, half
wrong, or backwards once benchmarked. Iterate over a list directly (don't index
into it by counter); when counting *down*, use `range(hi, lo, -1)` (the "use a
while loop instead" advice is the slow one); and `for i in N` vs `range(N)` is a
toss-up — pick whichever reads better.

Measured `bench_loop_idiom.gd`, N = 2,000,000, best-of-7, **Godot 4.8.dev**:

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

**In plain terms:** Godot has two flavors of common math helpers — the generic
`clamp`/`abs`/`max` that work on anything, and the type-specific `clampf`/`absf`/
`maxf` (for floats) and `clampi`/`absi`/`maxi` (for ints). The typed ones skip
the engine's "what type is this?" check and run noticeably faster in a tight loop.

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

**In plain terms:** annotating your variables with types (`var x: int = 0` instead
of `var x = 0`) is the single biggest performance win in GDScript — but it's
smaller than the often-quoted "40–47% faster," and a few related claims (`:=` is
slower, typed array iteration is faster) don't actually hold up.

Static typing itself is the biggest single win — but measure it before quoting a
number. The folklore figure is "~40–47% faster"; on this build, an int-arithmetic
hot loop with every variable, the loop counter, and the accumulator typed ran
**~1.35× (~25–28% faster)** than the same loop left untyped
(`bench_static_typing.gd`, N = 2M, best-of-7, Godot 4.8.dev). The win is real and
worth a blocking rule (**H2**, untyped `for`), but it's workload-dependent — the
40–47% claim is the high end, not the typical case.

**In plain terms:** an untyped variable is a *Variant* — a box that has to carry
its own type tag, and every operation on it first asks "what's in here?" before
doing the work. A typed variable is just an `int` (or `float`, …), so the compiler
emits the integer instruction directly. You're paying for the "what's in here?"
question on every single operation, and typing removes it.

One more thing the data kills: **`:=` is not slower than `var x: T =`.** They are a
**wash** (~1.03×) — `:=` *infers* a static type, so it produces the same typed
instructions *and* keeps the same compile-time win: the type is known, so method
calls on the variable are resolved and checked at parse time (autocomplete works, a
typo'd method is an error). `:=` is fully typed; only a bare `var x = …` with no
annotation falls back to Variant. The rule that bans `:=` (**H1**) is therefore a
*consistency / readability* rule (one obvious way to declare; the type is visible
at the point of declaration without chasing the right-hand side), **not** a
performance rule — and not a "but `:=` is untyped" rule either, because it isn't.
Don't justify it with speed; the speed is identical.

Two more widely-assumed wins that don't hold:

| Claim | Measured (Godot 4.8.dev) | Reality |
|---|---|---|
| `obj.method()` beats `obj.call(&"method")` | 1.19–1.21× | true, but modest — the real case against `call()` is **correctness** (typo → silent no-op), not speed → **H13** |
| iterating `Array[int]` beats untyped `Array` | 0.93–0.97× | a **wash** — typed iteration isn't faster here. The case for typed `.filter()`/`.map()` (**C3**) and typed `range()` (**C14**) is *correctness* (the result is silently untyped, #72566 / #110659), not performance |

This is the discipline the whole project runs on: a rule earns "blocking" only
when the data backs it. C3/C9/C14 are blocking because they're **correctness**
bugs; **H1** is blocking for *consistency* (the perf is a wash); the
perf-motivated rules that didn't measure up (L1/L2/L3/P22) are **advisory**.

---

## The folklore, overturned

**In plain terms:** three pieces of advice you'll see repeated online turn out to
be wrong on this engine version. The list below is the short "if you only
remember this much" version.

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
