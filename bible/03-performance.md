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

## 3a. Hot paths and cold paths

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
is in [4e (hot/cold data split, D5)](04-data-oriented.md). The through-line:
**spend your effort where the work actually repeats, in both code and data.**

---

## 3b. Dispatch — `match` vs `if/elif` vs a Callable table

**In plain terms:** when you need to pick between several actions based on the
value of one thing (a kind, a state, a tag), there are three usual ways to write
it. The numbers below say which one is actually fastest in GDScript — and the
common assumption ("`match` is the clean fast one") is wrong.

Branching on the value of one discriminator (a type code, enum, tag) is the most
common dispatch in gameplay code. The conventional choices are `match`, an
`if/elif` chain, or an `Array[Callable]` "jump table." Measured
(`bench_dispatch_mechanism.gd`, 600k rows, best-of-7, median of 5 runs, **Godot
4.8.dev**; baseline = `Array[Callable]` index = 1.00×, higher = faster):

| Construct | vs Callable table |
|---|---|
| `Array[Callable]` index | 1.00× |
| `match` + direct call | **0.64×** — *slower* than the Callable it would replace |
| `if/elif` + direct call | 1.01× |
| `if/elif` + inline body (no call) | **~2.1×** |
| `match`, 6 arms, hit the last | **0.37×** |
| `if/elif`, 6 arms, hit the last | 0.73× |

**In plain terms:** higher is faster. The Callable-table row is set to 1.00 so
everything else is a multiplier on it. So `match + call` at 0.64× is running about
two-thirds as fast as the Callable table; `if/elif` with the body inlined at ~2.1×
is more than twice as fast. The 6-arm rows show what happens when the answer is
the *last* arm checked — `match` drops to 0.37× (it slows down a lot as the list
grows), while `if/elif` only drops to 0.73×.

Two findings most people get wrong:

1. **There is no cheap "jump table" in interpreted GDScript.** `Array[Callable]`
   indexing isn't free, and `match` is *worse* than it at every arm count. The
   only construct that clearly beats the Callable table is an `if/elif` chain with
   the **body inlined** (no call) — ~2.1×.
2. **A value-only `match` is the slowest option, and it degrades with arm count.**
   Each arm carries pattern-matching machinery (type test, destructure, bind) even
   when you use none of it, and arms are scanned in order: at 3 arms `match` is
   ~1.5× slower than `if/elif`+call (0.64 vs 1.01); at 6 arms hitting the last,
   ~2× slower (0.37 vs 0.73).

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

## 3c. Call overhead & indirection

**In plain terms:** every step the engine takes to figure out *which* function to
run is work on top of the function itself. A direct call is cheap; going through
an object, a singleton, a name-lookup, or a list of subscribers all add bookkeeping
on the way in. The table below shows how much each step adds.

Every layer between the call site and the code costs. Measured
(`bench_dispatch_mechanism.gd`, 600k iters, best-of-7, median of 5 runs,
**Godot 4.8.dev `00932449c`**). The **ns/op column is the durable one** — it holds
to ~1–3% across runs, while the ratios beside it swing ~15% because the inline
baseline is the noisiest row in the table (10.9–13.7 ns) and every ratio divides by
it. Read ns for budgeting; read the ratio only for tier intuition. The inline
baseline is deliberately trivial (`acc += i + 1`), so the ratios are an *upper
bound* on relative overhead:

| Path | ns/op | × inline |
|---|---|---|
| inlined expression | 12.7 | 1.00 |
| `static func` on a `class_name`'d RefCounted | 45.4 | ~3.6 |
| lambda `.call`, no capture | 52.0 | ~4.1 |
| static fn passed as a `Callable` (`cb = Helper.add`) | 54.0 | ~4.3 |
| instance method on a cached ref | 55.6 | ~4.4 |
| lambda `.call`, captures a local | 58.6 | ~4.6 |
| autoload global identifier (`Bus.method()`) | 60.7 | ~4.8 |
| method-reference `Callable.call` (`obj.method` as a value) | 67.0 | ~5.3 |
| lambda wrapping a named fn (`func(x): f(x)`) | 86.6 | ~6.8 |
| `signal.emit()`, 0 listeners | 47.2 | ~3.7 |
| `signal.emit()`, 1 listener | 102.7 | ~8.1 |
| `get_node(^"X").method()` per call | 106.4 | ~8.4 |
| `signal.emit()`, 4 listeners | 263.9 | ~20.8 |

(The autoload row needs a real project with a registered `[autoload]`, so it's
measured separately — `tests/autoload_bench_proj/`, same session. In ns it needs
no normalization: that project's own instance-method row lands at 55.9 ns against
this bench's 55.6 ns, 0.5% apart across two processes. That agreement is the
argument for the ns column — it is comparable across projects and builds in a way
a ratio against a local baseline is not.)

**What a signal actually charges: one direct call per listener, plus 47.2 ns.**
The three signal rows decompose cleanly. An emit nobody subscribed to costs
**47.2 ns** — that is the dispatch machinery alone. The first listener adds
55.5 ns, against **55.6 ns** for a direct instance call: 0.2% apart. Listeners
two through four add 53.7 ns each. So *delivery* to a subscriber costs what
calling that subscriber directly costs, and the signal's own overhead is the
fixed 47.2 ns. (That row was added after the two-point decomposition predicted
~49 ns for it; the measurement came back 47.2 ns, which is the check that the
model isn't an artifact.) Two things follow, and they point in opposite
directions from the usual "signals are slow" reading: collapsing a **1-to-1**
signal into a direct call is a real ~47 ns saving, but **hand-rolling a multicast
to avoid signals does not pay** — four listeners through method-reference
`Callable`s costs 4 × 67.0 = 268 ns against the signal's 263.9 ns. Only a loop of
direct typed calls beats it (222 ns, ~16%), at the price of writing your own
subscribe/unsubscribe lifecycle. → **P18**, Part IV §4h.

The lambda/Callable rows are the addition. The findings: a **bare lambda call
sits in the static/instance tier** (~3.6×) — using a lambda as a predicate/comparator
is a normal indirect call, not expensive. **Capturing a local adds ~10%** (3.6 →
3.9). A **method-reference Callable** (`obj.method` passed as a value) costs a touch
more than calling the method directly (~4.7 vs ~4.3) — binding the object each call.
The one real anti-pattern is **wrapping a named function in a pass-through lambda**
(`func(x): return f(x)`): it double-dispatches — the `Callable.call` to the lambda
*plus* the inner call. The honest comparison is against the alternative you'd
otherwise write — **passing that same function as a `Callable` directly** (`cb =
Helper.add`, ~3.8×): the wrapper is **~6.5× vs ~3.8×, i.e. ~1.7× the cost for zero
benefit**. If you already have a named function, **pass the reference** (`f`,
`obj.method`), don't wrap it. → lint rule **P19** (advisory).

**In plain terms:** in this table higher means *slower* (the opposite of 3b's
table) — the inline baseline is 1.00, and ~3.6 means "about three and a half times
as long as just doing the work right there." In real money: doing the work inline
costs ~13 ns, a static helper call ~45 ns, a lambda or instance method ~52–59 ns,
an autoload ~61 ns, a `get_node()` lookup ~106 ns, and a signal emit with four
listeners ~264 ns — of which only 47 ns is the signal itself, the rest being the
four calls it makes on your behalf. Same answer at the end, very different cost to *get* to it —
though note the whole ladder spans about a quarter of a microsecond, so it only
shows up when you do it thousands of times per frame.

**In plain terms:** the further the engine has to travel to find the code you want
to run, the more it costs. Inlining the work is free — there's nothing to find. A
`static func` is just a known address. An instance method has to go through an
object; an autoload through a global singleton; a `get_node()` has to *walk the
scene tree by name* every single call; and a signal has to look up everyone who
subscribed and call each of them. Same answer, very different amounts of
bookkeeping.

Takeaways:

- **Cache node refs.** `get_node()` per call is ~1.9× worse than calling through a
  cached reference (106.4 vs 55.6 ns) — `@onready` it once so the lookup happens a
  single time, not every frame. → lint rule **(P3, reviewer)**.
- **A stateless helper belongs on a `class_name`'d RefCounted as a `static func`**
  (45.4 ns) — the cheapest indirection here, cheaper than an instance method
  (55.6 ns) or an autoload (60.7 ns).
- **A lambda is not expensive to call** (52.0 ns, same tier as a method) — but
  don't wrap a named function in one (`func(x): f(x)` is 86.6 ns, vs 54.0 ns to
  pass that fn as a Callable directly — ~1.6× for nothing); pass the reference.
  → **P19** (advisory).
- **Budget in ns, not multipliers.** A 60fps frame is 16,666,000 ns. A ~100 ns
  indirection has to happen **~1,600 times a frame** to cost 1% of it. Every row
  in this table is invisible below that rate — which is why the rules that cite
  it (P3, P18, P19) are about *hot loops*, not about code in general.
- **Signals decouple; they do not speed.** Emitting to even one listener costs
  about as much as a `get_node()` call, and it scales with listener count — four
  listeners is ~2.4× the one-listener cost. The reason to use a signal is that the
  sender doesn't need to know who's listening — that's an architecture win, not a
  speed one. In a hot path with a small, known set of consumers, call directly.
  Emitting a signal every `_physics_process` to one known listener is a perf bug
  dressed as architecture. → **P18**.

---

## 3d. Loops — three idioms, two of them folklore

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

```gdscript
# Bad — index-by-counter (L1), and a hand while for the descending pass (L2).
for i in range(items.size()):
    _use(items[i])
var n: int = items.size() - 1
while n >= 0:
    _cull(items[n]); n -= 1

# Good — iterate directly (~1.3×), descending range not while (~2.2×); typed for.
for it: Item in items:
    _use(it)
for i: int in range(items.size() - 1, -1, -1):
    _cull(items[i])
```

---

## 3e. Typed math functions

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

```gdscript
# Bad — untyped clamp/abs force Variant dispatch every call in a hot loop.
func _physics_process(_dt: float) -> void:
    velocity.x = clamp(velocity.x, -SPEED, SPEED)
    var d: float = abs(target.x - position.x)

# Good — typed *f variants skip Variant dispatch (~1.3× in a tight float loop).
func _physics_process(_dt: float) -> void:
    velocity.x = clampf(velocity.x, -SPEED, SPEED)
    var d: float = absf(target.x - position.x)
```

---

## 3f. Static typing & the things that are *not* faster

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
| iterating `Array[int]` beats untyped `Array` | 0.93–0.97× | a **wash** — typed iteration isn't faster here. The case for typed `.filter()`/`.map()` (**C3**) and typed `range()` (**C14**) is *correctness* (the result is silently untyped, #72566 / #72627), not performance |

This is the discipline the whole project runs on: a rule earns "blocking" only
when the data backs it. C3/C9/C14 are blocking because they're **correctness**
bugs; **H1** is blocking for *consistency* (the perf is a wash); the
perf-motivated rules that didn't measure up (L1/L2/L3/P22) are **advisory**.

### Script classes: typing pays on access, and costs you at the boundary

Everything above measured **builtin** types — `bench_static_typing.gd` types `int`
and `float` locals and nothing else. "Static typing is ~25–47% faster" is therefore
an int-arithmetic number, and it does not transfer to a `class_name`'d GDScript
type. That is a separate question with a different answer, and
`bench_scriptclass_typing_proj/` asks it across the shapes a record is actually
used in.

**In plain terms:** an untyped value is a box with a label on the outside saying
what is inside. Every time you use it, the engine reads the label first. Telling the
compiler the type means it can skip reading the label — that is where the speedup
comes from, and it is why *reading a field* or *calling a method* on a
properly-typed reference is faster.

But there is a second thing going on, and it runs the other way. Putting a value
*into* a typed slot means proving it belongs there. For an `int` that proof is
trivial. For one of your own classes the engine has to walk up the family tree:
"is this thing a `HitRecord`? No — is its parent a `HitRecord`? No — is *its*
parent…" and each step up costs about 6 ns. That walk is the fee, and it is charged
at the moment the value crosses from a box into a typed slot — not while you use it
afterwards.

So the two halves are: **typing what you already hold is free speed; converting
something you were handed costs a fee.** That is the whole finding, and it explains
every row in the table — the positive rows all use an already-typed reference, and
the negative rows all cross a boundary.

One more wrinkle, and it is the practically important one. There are two different
ways to cross, and they behave differently in a shipped game. `var x: T = value`
does its proof **only while you are developing**; when you export the game that
check is compiled out and disappears completely. `x as T` does the walk **always**,
in the editor and in the shipped game alike, because it has to — it promises to hand
you back `null` when the value is the wrong type, and it cannot know that without
looking. You are paying for the `null`. That is a good deal when you check the
`null`, and pure waste when you don't.

Measured on 4.8.dev `30caae98b` (editor build, N = 2M, best-of-7, **median of 15
runs, 1 discarded as contaminated**, n = 14):

| Shape | Typed vs untyped | Range | Reading |
|---|---|---|---|
| member read (`rec.v`) | **+24%** | +22 to +28% | typing a held reference pays |
| method call (`rec.bump(i)`) | **+14%** | +13 to +16% | pays |
| member write (`rec.v = i`) | **−0.2%** | flat | a wash, not a win |
| typed param pass | **−8%** | −14 to −5% | typed is *slower* |
| same, body never dereferences | **−9%** | −10 to −4% | so the cost is the call-site check, not the body |
| Variant → typed local | **−8%** | −11 to −3% | typed is *slower* |
| `x as TypedRec` | **−34%** | −35 to −32% | 27.3 → 41.5 ns |
| local assign from a typed source | **mid-to-high teens** | +15 to +26% | pays; magnitude not converged |
| `int` arithmetic (positive control) | **high 20s to high 40s** | +24 to +47% | the builtin win, reproduced — the harness's most volatile row |

**How those numbers were scrubbed, because it changed two of them.** A contended
machine inflates every row of a run together, so contamination has to be discarded
**per run, wholesale** — not per row by eyeballing each row's own min and max. The
filter: take the median of all of a run's untyped baselines plus the depth-probe
baseline, and drop the entire run if that exceeds the session median by >10%. One
run in 15 failed it. Scrubbing that way collapsed `Variant → typed local` from an
apparent "−6%, range −16 to +31%" to a clean **−8%, range −11 to −3%, entirely
negative** — the positive tail was one bad run leaking in, not real spread. That row
carries half the `ASSIGN_TYPED_SCRIPT` story, so the difference matters.

A discard rule can of course flatter the thing it is filtering, so the filter was
checked against that: recomputing every row with and without it moves each median by
at most 0.8pp, **in both directions** (`member read` gets 0.8pp *worse*, `int
builtin` 0.65pp better, every boundary-crossing row unchanged to within 0.05pp). So
it is close to a no-op on the point estimates, and its real job is range hygiene —
keeping one bad run from inventing a tail. The discarded count is reported alongside
n so the reader can judge.

**Do not trust `member write` alone as the contamination tell.** It is tempting
because it should read flat, but at 16–17 ns absolute a 0.3–0.5 ns jitter is already
multiple percent, so it produces false alarms on good runs — and it misses runs
where only one or two rows are locally contaminated while it reads dead flat.
Require at least two independent indicators to move together.

**The last two rows are bands on purpose, and not because of within-session noise.**
Their medians drift across whole *sessions* on the same machine: repeated batches
put `int builtin` at +28%, +33%, +38%, +46% at different times of day. Positional
split-halves inside one batch look converged and will not catch this, because both
halves share that session's ambient state. Nothing in this section's argument rests
on either row — `int builtin` exists only to prove the harness can see the builtin
win at all (it has been positive in every run ever taken, minimum +18%), and the
repo's quoted "~25–47% on builtins" comes from `bench_static_typing.gd`, a different
benchmark. Every load-bearing row is in the converged set.

So the line is not builtin-vs-script-class. It is **whether a script-type check
happens**. Hold a reference that is already statically typed and typed access wins
by 14–25%. Cross a Variant boundary into a typed slot and you pay for the crossing,
which is why two rows go negative.

**The two penalties do not have the same lifespan**, and this is the part worth
remembering. Read the opcodes in `modules/gdscript/gdscript_vm.cpp`:

- `OPCODE_ASSIGN_TYPED_SCRIPT` — the **entire** check body sits inside
  `#ifdef DEBUG_ENABLED`. An exported release build does no check, so the −9% /
  −8% assign-and-param penalty is an editor-build artifact.
- `OPCODE_CAST_TO_SCRIPT` — the `#ifdef` covers only the freed-object and
  non-object asserts. The `while (src_type)` walk up the script inheritance chain
  is **outside** it. Unconditional, in every build.

The walk is depth-dependent, which gives a way to confirm from inside a debug build
that it really is the mechanism. Same instance (a `D4`), cast to targets at
increasing distance up its own chain:

| Cast target | ns/op (median of 14 clean runs) |
|---|---|
| no cast (baseline) | 27.3 |
| `as D4` — 0 links | 41.5 |
| `as D2` — 2 links | 53.1 |
| `as DepthBase` — 4 links | 65.5 |

Linear: **~14 ns fixed + ~6 ns per inheritance link** (5.98 ns/link across the four
links). A deep class hierarchy makes every `as` against it worse, permanently.

**Caveat, stated plainly:** the release half is read from source, **not measured**.
No installed editor matches an installed export template (editors 4.8.dev / 4.6 /
4.4.1 against templates 4.7.stable / 4.5.beta5), and a template refuses both
`--path` and a CWD project (`disable_path_overrides`), so a release run needs a
`template_release` built from this commit. Until that exists, treat "the assign and
param penalties vanish in release" as a confident reading of the `#ifdef`, not a
measurement. The `as` finding needs no such caveat — the walk is unconditional in
the source and the depth probe measures it directly.

**What to do with this:**

- Type your records, fields and locals as usual. Holding a typed reference is a
  14–25% win on access and costs nothing anywhere.
- Prefer `var x: T = value` over `x as T` when the type is guaranteed: **~8 ns
  cheaper** in a debug build (33.2 vs 41.3 ns), and free in release where `as` never
  is.
- Reach for `as` only when the value genuinely might not be a `T`, **or** when the
  guarantee comes from data you don't control — a typed assign's check is gone in
  release, so `as` is the only form that checks identically in both builds. You are
  paying 14 ns + 6 ns/link **for the `null`** it hands back on a mismatch — worth it
  exactly when you branch on that `null`, and wasted otherwise: an unchecked `as`
  only defers the failure to the next access. Note the
  asymmetry in failure behavior: `var x: T = wrong_thing` errors loudly in debug and
  is *unchecked* in release, while `as` returns `null` identically in both.
- Best of all, retype the source so no crossing happens — the precedence point
  **H14c** already makes on readability grounds now has a number behind it.
- Remember `is` does not narrow (**H14**): `if x is T:` then `x.field` still pays
  Variant dispatch on the access. The guard buys safety, not speed.

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
