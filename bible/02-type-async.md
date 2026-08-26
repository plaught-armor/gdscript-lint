# Part II — Type system & async

GDScript is dynamically typed by default, but the compiler emits a separate, much
faster instruction stream when it can prove every operand's type. The first half
of this part is about staying on that fast path — declaring types so the compiler
takes it, and avoiding the patterns that silently fall back to Variant. The
second half is `await` and coroutines: a small, simple-looking feature with a
disproportionate number of non-deterministic, hard-to-reproduce traps. They're
grouped together because the failure mode is the same in spirit — code that
*looks* correct, runs most of the time, and silently does the wrong thing when
the runtime shape diverges from the source-level expectation.

Draws from [`../rules/type-async.md`](../rules/type-async.md), with engine-bug
cross-references into [`../rules/engine-bugs.md`](../rules/engine-bugs.md).

---

## 2a. Static typing is the single biggest perf win

Static typing is the floor. Every other rule in Part III assumes you've already
paid this one cost. Typed instructions run measurably faster than the
Variant-dispatched equivalents — not because the language is somehow optimizing
your code, but because the compiler emits genuinely different bytecode for typed
operands (typed add, typed compare, typed property access) and falls back to a
boxed-Variant path the moment it can't prove a type.

The often-quoted figure is "~40–47% faster"; measured on Godot 4.8.dev
(`bench_static_typing.gd`, N = 2M, best-of-7) a fully-typed int-arithmetic loop
ran **~1.35× (~25–28% faster)** than the same loop untyped. The win is real and
workload-dependent — 40–47% is the high end, not the typical case. The full
discussion and the "what's *not* faster" table are in
[3f](03-performance.md#3f-static-typing--the-things-that-are-not-faster).

**In plain terms:** an untyped variable is a *Variant* — a box that carries its
own type tag, so every operation first asks "what's in here?" before doing the
work. Typing removes that question; the compiler emits the `int`/`float`
instruction directly.

And speed is often the *smaller* win. When the compiler knows a variable's type, it
knows what methods and properties that type has — so `x.do_thing()` is resolved and
checked at parse time. You get autocomplete on `x`, and a misspelled method or a
wrong-arity call is a **compile error**, not a silent runtime surprise. On an
untyped Variant the compiler can't check anything: every `x.do_thing()` is resolved
at runtime, and a typo only blows up (or quietly no-ops) when that line happens to
run. The day-to-day value of typing is as much "the editor and compiler stop you
guessing" as it is raw throughput. Note this win survives `:=` — inference still
produces a concrete static type, so you keep the method resolution; you lose it
only with a bare `var x = …` that has neither an annotation nor `:=`.

### H1 — Always `var x: Type = value`, never `:=`

`:=` infers the type, but the inferred type isn't always what you'd write by
hand, and "inferred" is harder to grep than "declared." More importantly: a
**declared** type at every binding is what we want the codebase to look like —
explicit, scannable, with the type *at the point of declaration*, not somewhere
the reader has to chase. The cost difference between `:=` and `var x: T = …` is
zero (both produce typed instructions when the RHS is typed); the rule is about
discipline, not bytecode.

```gdscript
# Bad — inferred. Reader has to look at the RHS to know what x is.
var x := compute_thing()

# Good — declared. Type is right there.
var x: SomeType = compute_thing()
```

This applies everywhere a binding introduces a name: locals, parameters, return
types, members, `for` vars. → lint rule **H1**.

### H2 — Type the `for` loop variable

An untyped iteration variable defeats every optimization in the loop body —
every operand is a Variant, every operation goes through dispatch.

```gdscript
# Bad — every `e.x` inside is Variant-dispatched.
for e in enemies:
    e.tick(delta)

# Good — `e` is typed, member access is direct.
for e: Enemy in enemies:
    e.tick(delta)
```

This is **blocking** because untyping the loop var costs you the entire loop's
worth of dispatch. → lint rule **H2**.

A subtlety covered in Part III: typing the loop variable for *iteration* is the
win. Typing the integer counter in `for i: int in range(N)` is fine but doesn't
itself speed anything up (it's break-even — see L3 in Part III). The win comes
when the loop body actually uses the variable as a typed member-access target.

### What "fast path" actually means

The GDScript compiler has two parallel instruction streams: the typed
instructions, which know the operand types and skip the dispatch table, and the
untyped instructions, which call into the Variant machinery for every operation.
A function is on the typed path when **every** operand can be proved at compile
time. One untyped local is enough to drag the surrounding expression off the
typed path; one untyped collection element is enough to drag a loop body off it.

The rules in this part — H1, H2, H3 enum boundary, H4 typed signal params, H7
float→int narrowing — exist to keep the compiler's type inference unbroken end
to end. The "use typed math fns in hot paths" rule (P22, below) is the same idea
applied to standard library calls.

---

## 2b. Typed-collection traps

**In plain terms:** you can write `Array[Enemy]` on a variable, and the line
looks type-checked — but some built-in operations hand back a plain untyped
`Array`, and the language quietly accepts the mismatch. The variable says it
holds typed items; it actually doesn't, and the bug shows up much later.

Static typing covers locals and parameters cleanly. The traps live at the
collection boundary, where a typed declaration meets a returns-Variant API.

### C3 — `.filter()` / `.map()` return untyped Array

`Array[T].filter(...)` returns `Array`, **not** `Array[T]`. Direct assignment to
a typed local fails silently — you get an untyped result that types-checks now
and breaks later. The workaround is `Array.assign()`:

```gdscript
# Bad — types check, but `result` is actually untyped Array.
var result: Array[BattlePawn] = queue.filter(func(p): return is_instance_valid(p))

# Good — `.assign()` enforces the element type.
var result: Array[BattlePawn] = []
result.assign(queue.filter(func(p): return is_instance_valid(p)))
```

Tracked as [#72566](https://github.com/godotengine/godot/issues/72566). **Re-tested
on Godot 4.8.dev (see [1a](01-engine-bugs.md#1a-typed-filter--map-return-untyped-array)):
`.filter()` now returns a *typed* result — fixed — but `.map()` still returns an
untyped `Array`.** Until your minimum Godot has both fixed, keep the `assign()`
habit for both; it's harmless on the already-fixed `.filter()` path. → lint rule
**C3** (engine bug, blocking).

### C14 — `range()` produces untyped Array

`range(N)` returns `Array` (untyped). Assigning the result to `Array[int]`
silently produces an untyped collection. This is a typing bug, not a loop-speed
bug — iteration over `for i in range(N)` is fine (3d measures it as
break-even with `for i: int in N`); the breakage is at the *assignment*:

```gdscript
# Bad — silently untyped despite the annotation.
var indices: Array[int] = range(10)

# Good — explicit construct. (Array[int] is C14's subject: a Packed*Array has no
# untyped-range bug, so S6's "prefer Packed" doesn't apply to this illustration.)
var indices: Array[int] = []  # gdlint: ignore[S6]
indices.assign(range(10))
```

Tracked as [#72627](https://github.com/godotengine/godot/issues/72627) ("Cannot
cast typed arrays using type hints") — the range-specific report
[#110659](https://github.com/godotengine/godot/issues/110659) was closed as its
duplicate. → **C14**.

### H10b — Type the container, don't probe it

**In plain terms:** if a function takes a collection, say exactly what's in it
in the signature — don't take a vague "anything" and then ask "what did I
actually get?" inside the body. The signature is the contract; checking shapes
at runtime hides the contract and lets the wrong data through.

When you control both the producer and the consumer of a collection, declare the
parameter with its full type — `Dictionary[K, V]`, `Array[T]`, `PackedStringArray`,
typed `Resource` subclass. Don't take `Dictionary`/`Array`/`Variant` "for
flexibility" and then branch on `typeof()` inside the body. The probing pattern
hides the contract, pays Variant dispatch per access, and silently accepts the
wrong shape.

```gdscript
# Bad — signature lies; body probes shape per access.
static func bfs_distances(start: String, edges: Dictionary, max_depth: int) -> Dictionary:
    var neighbors: Variant = edges.get(cell, PackedStringArray())
    if typeof(neighbors) == TYPE_PACKED_STRING_ARRAY:
        ...
    elif neighbors is Array:
        ...

# Good — signature is the contract.
static func bfs_distances(
    start: String, edges: Dictionary[String, PackedStringArray], max_depth: int
) -> Dictionary[String, int]:
    if not edges.has(cell):
        continue
    var neighbors: PackedStringArray = edges[cell]
```

The legitimate exceptions are *boundaries*: `JSON.parse_string`
([#97137](https://github.com/godotengine/godot/issues/97137)), `@tool` scripts,
plugin and reflection code, save-format migration. Convert to typed at the
boundary; downstream takes the typed form.

**4.8.dev: this is a correctness rule, not a perf one.** Summing a small
`Dictionary` passed as `Dictionary[String, int]` vs untyped `Dictionary` measured
**~1.00× (a wash)** at this scale — the function-call and hash-iteration cost
swamp any element-typing delta (`bench_param_types.gd` → H10b). So don't sell
H10b on speed; its value is the honest signature — the contract is visible, the
body can't silently accept the wrong shape, and you skip the `typeof()`/`is`
probing. (The probing *body* would cost more; a clean typed param vs a clean
untyped param is even.)

### H14 / H14b — No redundant `as` after `is`, no `as` after typed access

**In plain terms:** checking `if x is Enemy` does **not** tell the compiler
anything — it only decides which branch runs. Inside that branch `x` is still
whatever it was declared as, so `(x as Enemy).foo` pays a real conversion every
single time you write it. Name the thing once (`var e: Enemy = x`) and use the
name. Typed dictionaries and arrays are the opposite case: the value really does
come out with its type attached, so an extra cast there is pure paperwork.

**`is` does not narrow, and the editor lies about it.** Measured 4.8.dev with
`unsafe_method_access=2`, inside `if bt is Dictionary:` the analyzer still reports
`bt` as `Variant` — "The method `keys()` is not present on the inferred type
`Variant`" — and a class-typed var behaves the same (`if n is Node2D:` leaves `n`
a `Node`, so `n.flip_h` trips `unsafe_property_access`). Autocomplete narrows
because `modules/gdscript/gdscript_editor.cpp:2488` special-cases the `is` guard,
a path the source itself labels *"Super dirty hack, but very useful"*. It feeds
completion only; the type checker and the compiler never see it. So the inline
cast is not *redundant*, it is *repeated* — and the bare access it would be
replaced by is an unsafe dynamic lookup, not a typed one.

Typed-container access is the genuinely narrowed case: `Dictionary[K, V].get(k)`,
`dict[k]`, `Array[T][i]` all return typed `V`/`T` (verified — `var s: String =
d[0].x` on a `Dictionary[int, Foo]` fails to parse with "Cannot assign a value of
type int"). Re-casting those *is* a wasted round-trip.

```gdscript
# Worst — the cast repeats the runtime check on every access.
if x is Enemy:
    (x as Enemy).take_damage(5)
    (x as Enemy).flash()

# Better, but every access is an unsafe dynamic lookup (and warns).
if x is Enemy:
    x.take_damage(5)

# Best — one check, then statically typed accesses. Hoist the bind above any
# loop the guard permits; a bind repeated per iteration costs what the cast did.
if x is Enemy:
    var enemy: Enemy = x
    enemy.take_damage(5)
    enemy.flash()

# Bad — `_cells.get(path)` already returns CellState (H14b).
var cs: CellState = _cells.get(path) as CellState

# Good.
var cs: CellState = _cells.get(path)
```

Containers carry their type — trust them. **4.8.dev: measured**, ns per access,
2M iterations, best of 7 (`bench_redundant_cast.gd`): typed local bound once
above the loop **23.0**, bare `v.x` **44.7**, `(v as Foo).x` **61.2**, typed local
re-bound each iteration **61.7**. The bind is both the fastest and the only form
the type checker can see; the per-use cast is the slowest and buys nothing. On a
typed `Dictionary[int, Foo]`, `(d[0] as Foo).x` ran ~1.5× `d[0].x`.
→ **H14**, **H14b**.

### H4 — Type every signal parameter

Signal declarations with untyped parameters force every connected handler to
receive Variants, defeating the whole optimization chain on the receiver side
([#110573](https://github.com/godotengine/godot/issues/110573)):

```gdscript
# Bad — handler receives Variant.
signal hit_landed(target, damage)

# Good — typed contract, handler stays on the fast path.
signal hit_landed(target: Enemy, damage: int)
```

**4.8.dev: the win is correctness, not emit speed.** Emitting 1M times to a
handler via a typed-param signal vs an untyped-param signal measured **~1.00×**
(`bench_param_types.gd` → H4) — the signal-dispatch cost (≈115 ns/emit; see 3c)
dwarfs any param-typing delta, so you won't find it in a benchmark. The
real reason to type signal params is #110573: a typed signal validates handler
signatures at `connect` time and documents the payload — a wrong-arity or
wrong-type handler is caught at the boundary instead of silently receiving a
mis-shaped Variant. Type them for the contract, not the clock.

### H7 — Float→int narrowing is silent

Passing `5.0` to an `int` parameter doesn't error — it silently narrows. The
typed-call machinery still takes the Variant path for the conversion, and the
fractional part is lost without warning.

```gdscript
# Bad — `1.5` silently becomes `1`.
arr.resize(1.5)

# Good — explicit cast surfaces intent.
arr.resize(int(1.5))
```

Pair with the P12a literal-matches-param table in `style.md`: most narrowing
bugs originate from a literal that should have matched the declared type (`5`,
not `5.0`). **4.8.dev: confirmed** — `Array.resize(2.9)` yields `size()==2`, the
fractional part dropped with no error (`repro_typing_traps.gd` → H7).

### H12 — `@export var` of a Resource type defaults to `null`

`@export var def: ItemDef` doesn't get a default-constructed `ItemDef` — an
*unassigned* export defaults to `null`, and any code that touches `def.field`
before something assigns one crashes with "Cannot access property on null
instance." This is **by design and permanent** — an unassigned `@export`
Resource is `null` on every Godot version, 4.6 included; nothing "fixes" it.
The discipline is a boot validator that errors on a still-`null` `@export`, so
the failure surfaces at the editor boundary instead of at first use. See
`style.md` M10 / M10a.

Distinct, and easy to conflate with the above:
[#110394](https://github.com/godotengine/godot/issues/110394) — *"Resource
silently fails to load with specific combination of @export/preload/globals/
script references."* There an `@export` Resource that **is** assigned in the
inspector silently loaded as `null` at runtime under a particular preload /
cyclic-script arrangement — correct in edit mode, `null` at play, **no error
logged**. That one *was* a bug, fixed in **4.6** by
[PR #109345](https://github.com/godotengine/godot/pull/109345) ("Prevent
shallow scripts from leaking into the `ResourceCache`"). The same boot
validator catches it too; on a ≥ 4.6 target the silent-corruption path itself
is gone, but the by-design null-default above is not — keep the validator.

```gdscript
# Bad — trusts the @export to be non-null. An unassigned ItemDef is null; the
# first field read crashes with "Cannot access property on null instance."
@export var def: ItemDef
func _ready() -> void:
    _stack_max = def.max_stack        # boom if the slot was left empty in the editor

# Good — boot-validate the export once; fail loud at the editor boundary (M10).
@export var def: ItemDef
func _ready() -> void:
    if def == null:
        push_error("[pickup] def not assigned"); return
    _stack_max = def.max_stack        # trusted past the guard, no per-use null check
```

### H11 — Typed Dict + JSON.parse_string

`JSON.parse_string` returns an untyped `Variant`. Assigning the result to a
typed `Dictionary[K, V]` doesn't enforce the element types; you'll get a runtime
crash the first time the inner shape diverges from what the annotation claimed.
[#97137](https://github.com/godotengine/godot/issues/97137). Treat JSON as a
boundary — convert to the typed shape explicitly at the conversion site, don't
let the annotation lie.

**4.8.dev (refines this):** the *checked* conversion path is better than "silently
accept, crash later." `Dictionary[String, int].assign(JSON.parse_string('{"a":
"not-an-int"}'))` raises **at the `assign()`** — `"Unable to convert value at key
'a' from 'String' to 'int'"` — and leaves the destination empty rather than
admitting the bad value (`repro_typing_traps.gd` → H11). So `.assign()` validates
element types eagerly. The trap that remains is a *direct* annotated assignment of
an untyped parse result without `.assign()`; the discipline (convert explicitly at
the boundary, prefer `.assign()`) is what makes the failure loud and immediate.

```gdscript
# Bad — the annotation lies. parse_string returns Variant; the inner types are
# never checked, so a bad shape rides in and crashes at the first typed read.
var scores: Dictionary[String, int] = JSON.parse_string(text)

# Good — treat JSON as a boundary; .assign() validates eagerly and fails loud.
var scores: Dictionary[String, int] = {}
scores.assign(JSON.parse_string(text))   # raises HERE if a value isn't an int
```

### H3 — Enums are an `int` at runtime; type the boundary

GDScript enums are `int` under the hood. The compiler will accept a bare `int`
where an enum-typed parameter is declared (it emits a warning, but it works).
The discipline is: at API boundaries, declare the enum type — registry public
methods, `@export var slot: ItemRegistry.Id`, signal parameters. Inside hot
loops or save-format fields, `int` is the right choice (`PackedInt32Array` can't
carry an enum type; save slots round-trip as `int`). This is covered in detail
in [`../rules/dod.md`](../rules/dod.md) D10/D10a. **4.8.dev: confirmed** —
`typeof(SomeEnum.MEMBER) == TYPE_INT` (`repro_typing_traps.gd` → H3).

```gdscript
# Bad — bare int at the boundary. Caller can pass 999; no autocomplete, no check.
func get_def(slot: int) -> ItemDef:
    return ALL[slot]

# Good — enum-typed boundary (compiler-checked); int stays for the wire format.
enum Id { NONE, POTION, SWORD_GRIP }
func get_def(slot: Id) -> ItemDef:
    return ALL[slot]
@export var start_slot: Id                    # designer picks from a named list
var wire: PackedInt32Array = [Id.POTION]      # save round-trips as int
```

---

## 2c. Null checks: `not x` vs `x == null` (S9)

**In plain terms:** `if not x:` is *not* a null check. It fires for the whole
"empty" family — null, zero, `""`, empty containers, `false`, and even a zero
vector — not just for "unset." If 0 or empty is a real value for `x`, `not x`
treats it as "nothing" and misfires. Use `x == null` when you specifically mean
"unset."

`if not x:` tests `x`'s *truthiness*; `if x == null:` is an equality test against
null. They give the same answer only when the falsy set collapses to "just null"
— i.e. when `x` is an Object/Node ref. Measured on 4.8.dev
(`tests/repro_null_checks.gd`):

| `x` | `not x` | `x == null` |
|---|---|---|
| `null` | true | true |
| `0` / `0.0` | true | false |
| `""` | true | false |
| `[]` / `{}` | true | false |
| `false` | true | false |
| `Vector2.ZERO` / `Vector3.ZERO` | **true** | false |
| `5` / `"a"` / `[1]` | false | false |
| freed Node (≥4.4) | true | true |

The standout is the zero-vector row: `Vector2.ZERO` is **falsy**, so
`if not velocity:` fires when the entity is merely *stationary*. The same trap
hits every primitive where 0/empty is meaningful — `if not damage:` at 0 damage,
`if not name:` on `""`, `if not arr:` on an empty (not absent) array.

```gdscript
# Bad — fires when stationary (Vector2.ZERO is falsy), and at 0 damage / "".
if not velocity: stop()
if not damage:   return
# Good — say exactly what you mean.
if velocity == Vector2.ZERO: stop()
if damage == 0:              return
if attacker == null:         return   # optional Object ref: explicit reads as intent
```

**Rules:**

- **Primitive / vector where 0 or empty is a valid value** → never `not x`. Use
  `x == null` (if nullable) or the explicit test you actually mean: `x == 0`,
  `x.is_empty()`, `vec == Vector2.ZERO`.
- **Object / Node ref, optional** → `if x == null:` reads as intent and sidesteps
  the freed-Node truthiness history (**H8**,
  [#59816](https://github.com/godotengine/godot/issues/59816) — on ≤4.3 both `not`
  and `== null` lied about a freed Node; fixed 4.4). For a node that may be freed
  out from under you, `is_instance_valid(x)` is the belt-and-suspenders check
  (Part I, C5). It answers liveness completely — a freed ref never comes back as
  a *different* live object (Part I, 1c).
- **`if not x` is correct** only when null *and* 0 *and* empty *and* false all
  genuinely mean "absent" — then it's the concise, right form.

**Perf is not the tiebreaker.** `== null` is marginally cheaper — `not x` first
materializes `x` as a bool (a type-dispatched truthiness cast on a `Variant`)
then negates, while `== null` is one direct compare — but measured the gap is a
wash-to-~1.2× over 2M iterations: single-digit-ns, far below the frame budget.
Choose on correctness; the speed is a rounding error (same verdict as H1 `:=`,
H4 typed signals). Not lintable — the right form depends on `x`'s static type,
which a text linter can't see — so this stays a reviewer / `style.md` **S9** call.

---

## 2d. Lambda capture semantics

**In plain terms:** a lambda is a small inline function. The surprise that bites:
the way a lambda "remembers" outside variables is different for local ones than
for object fields — so a counter you increment inside the lambda may not actually
go up where the caller can see it.

Lambdas are ordinary GDScript closures — use them freely. The one foot-gun worth
knowing is capture semantics. First, two things that are *not* foot-guns: how much
a lambda costs to call, and whether to extract its body.

### Lambda dispatch cost — a bare lambda call is cheap; one anti-pattern isn't

Measured (`bench_dispatch_mechanism.gd` §2, 4.8.dev — see Part III §3c for the full
dispatch table this slots into):

- A **bare lambda `.call` (~3.6× inline) sits in the static-func / instance-method
  tier.** Using a lambda as a `filter()`/`map()`/`sort_custom()` predicate is a
  normal indirect call, not an expensive one.
- **Capturing a local adds ~10%** (~3.6 → ~3.9×). Small.
- **Extracting the body to a named method is perf-neutral** — a named method called
  through the same higher-order path costs about the same as the inline-body lambda.
  So inline-vs-extract is purely a readability / testability call. (This is the
  measured epitaph for the retired S1 rule: it was a formatter workaround, and it
  has no performance successor — there is no speed reason to prefer either form.)
- **The one real anti-pattern: wrapping a named function in a pass-through lambda**
  — `func(x): return f(x)`. That double-dispatches: the `Callable.call` to the
  lambda *plus* the inner call to `f`. Measured against the **real alternative** —
  passing that same `f` as a `Callable` directly (~3.8×) — the wrapper is ~6.5×,
  **~1.7× the cost for nothing** (an extra GDScript frame between the `Callable`
  invocation and `f`'s body). If you already have `f`, **pass the reference** —
  `arr.map(f)`, not `arr.map(func(x): return f(x))`. And build the `Callable`
  once — never reconstruct a lambda inside a hot loop (each rebuild is a fresh
  allocation). Flagged **P19** (advisory).

```gdscript
# Bad — pass-through lambda double-dispatches.
arr.map(func(x): return _double(x))
# Good — pass the reference.
arr.map(_double)
```

### H6 — Capture by-value for locals, by-ref for members

**In plain terms:** when a lambda uses a *local* variable from outside, it
takes a snapshot of the value at the moment the lambda was created — changes
inside the lambda never reach back out. When it uses a *field on the object*,
it goes through the object itself, so changes do stick. To share writable state
with a lambda, use a field (or a list/dictionary, which the lambda can mutate
through its reference).

Lambdas capture **locals by value at lambda construction time**, and **members
by reference through `self`**. This produces a confusing asymmetry: mutating a
captured local inside the lambda has no effect on the outer local, but mutating
a member through `self` does. Tracked as
[#69014](https://github.com/godotengine/godot/issues/69014).

```gdscript
# Bad — the outer `count` stays 0; lambda captured the value `0`.
var count: int = 0
arr.for_each(func(item):
    count += 1
)
print(count)  # 0

# Good — `_count` is a member, mutated through self.
var _count: int = 0
arr.for_each(func(item): _count += 1)   # member mutated through self
print(_count)  # arr.size()
```

The rule is: if a lambda needs to share writable state with its caller, use a
member variable, or pass a mutable container (`Array`, `Dictionary`) — those are
captured by their reference, and mutations through the reference are visible.
Don't try to share a local `int` or `bool` by capturing it; the value
semantics will silently lie.

**4.8.dev: confirmed** — a lambda that does `local_v += 1; _member_v += 1` leaves
the outer `local_v` at `0` (captured by value) while `_member_v` becomes `1`
(mutated through `self`) (`repro_typing_traps.gd` → H6).

→ lint rule **H6**.

---

## 2e. `await` and coroutines

**In plain terms:** `await` pauses your function and continues it later — when
some signal fires. While it's paused, the world keeps moving: the thing you
were waiting on can be deleted, the scene can change, the signal may never
come. Most bugs in this section are about code that assumes "the next line
runs right after" when it really doesn't.

`await` looks like an expression, but it's a control-flow primitive that
suspends the current function and resumes it on a future signal. Three
properties of that mechanism produce most of the bugs:

1. **Suspension can outlive the awaited object.** Between `await` and resume,
   anything can happen — the node may have been freed, the scene may have
   changed, the signal may never fire.
2. **Resume scheduling is non-deterministic across concurrent coroutines.** Two
   coroutines awaiting the same signal don't have a guaranteed resume order.
3. **`await` in `_ready()` pauses tree construction**, with effects that depend
   on what else is going on in the frame.

### M1 — No `await` in `_ready()`

**In plain terms:** `_ready()` is the engine's "you're set up now" hook —
other parts of the game expect it to finish before they keep going. If you
`await` inside it, the function pauses and the rest of the setup happens
much later, so anything that depended on "everything's ready after `_ready`"
silently isn't.

`_ready()` runs once when a node enters the tree. The scene-tree machinery
assumes it returns synchronously: children's `_ready` is called after the
parent's, deferred calls scheduled in `_ready` fire next frame, signals
connected in `_ready` are live by the next `_process`. An `await` inside
`_ready` breaks that contract — the rest of the function runs in some later
frame, and code that depended on "everything is set up after `_ready` returns"
silently breaks.

```gdscript
# Bad — `_ready` returns at the await; init is incomplete when parent assumes it's done.
func _ready() -> void:
    await get_tree().process_frame
    _spawn_initial_enemies()

# Good — split: synchronous _ready, deferred follow-up, or a separate coroutine.
func _ready() -> void:
    call_deferred(&"_after_ready")

func _after_ready() -> void:
    _spawn_initial_enemies()

# Or: explicit coroutine the caller can start when it's safe to.
func boot() -> void:
    await get_tree().process_frame
    _spawn_initial_enemies()
```

**4.8.dev: confirmed** — calling an awaiting method and reading a flag it sets
*after* its `await`, the flag is still `false` on the next line: the `await`
returns control to the caller and the post-`await` code runs in a later frame
(`repro_async2_proj/` → M1).

`call_deferred` runs at end of the current frame, after the current call stack
unwinds — the right tool for "do this after init finishes, but in the same
frame's idle phase." `process_frame` waiting belongs in an explicit
caller-driven coroutine, not in `_ready`. → **M1**.

### M2 — Signal `await` needs a timeout and a validity check

**In plain terms:** if you wait for a signal that never arrives, your function
just sits there forever. Always race the wait against a stopwatch, and after
the wait ends, check that whatever you were waiting on still exists before you
use it — it might have been deleted while you were paused.

A bare `await some_signal` blocks forever if the signal never fires. In gameplay
code that's almost always a bug waiting to happen — the combat animation
finishes early, the network packet never arrives, the awaited node gets freed
mid-animation. The recovery pattern is a `SceneTreeTimer` racing the real
signal, plus an `is_instance_valid()` after the resume.

```gdscript
# Bad — hangs forever if anim never finishes (freed mid-attack, etc.).
await player.animation_finished

# Good — race against a timeout, validate the object on resume.
var timer: SceneTreeTimer = get_tree().create_timer(2.0)
await Signal.any([player.animation_finished, timer.timeout])
if not is_instance_valid(player):
    return  # player was freed during the await — bail
```

The `is_instance_valid()` after resume is the C5 pattern
([#72629](https://github.com/godotengine/godot/issues/72629)) — `await` on a
freed object leaks or crashes; the validity check is the prescribed defense.
Any `await` whose target was a `Node` needs the validity check on the other
side. → **M2**, cross-refs **C5** in `engine-bugs.md`.

### M3 — Concurrent coroutine race conditions

**In plain terms:** if two paused functions are both waiting on the same
signal, when the signal fires they wake up in an order nobody promised. If
both then try to change the same thing, you get a different result every run.
Fix it by making one function in charge of the change and having the others
just watch.

Two coroutines awaiting the same signal do **not** have a guaranteed resume
order. If both want to act on the same mutable state, you have a race condition
that reproduces inconsistently across runs:

```gdscript
# Bad — both coroutines await `door_opened`; resume order is non-deterministic.
func enter_room_a() -> void:
    await door.door_opened
    player.position = room_a_spawn  # may or may not win the race

func enter_room_b() -> void:
    await door.door_opened
    player.position = room_b_spawn  # may or may not win the race
```

The fix is the standard "one writer, many readers" pattern: have a single
authoritative coroutine drive the state change, and have observers poll a flag
or subscribe to a different signal that only the writer emits.

```gdscript
# Good — one writer (the door), one signal per state, no race.
func enter_room_a() -> void:
    await door.entered_room_a
    player.position = room_a_spawn

# Inside Door:
func _on_door_opened() -> void:
    if target_room == &"a":
        entered_room_a.emit()
    else:
        entered_room_b.emit()
```

When the design genuinely needs multiple coroutines to converge on the same
event, gate the shared state behind a single coroutine that polls a flag the
others set:

```gdscript
# Driver coroutine — owns the mutation.
var _ready_count: int = 0
func _all_ready() -> void:
    while _ready_count < expected:
        await get_tree().process_frame
    _apply_outcome()

# Observers — increment the flag, don't touch shared state directly.
func _on_arrived() -> void:
    _ready_count += 1
```

→ **M3**.

### M6 — Connecting a signal to a temporary object

`obj.signal.connect(temp.method)` where `temp` falls out of scope at end of
function silently disconnects when `temp` is freed (it's a `RefCounted` with no
other holder). The connection succeeds, the signal fires, no handler runs.

```gdscript
# Bad — `helper` is freed at function exit; the connection dies with it.
func setup_listener() -> void:
    var helper: RefCounted = MyHelper.new()
    button.pressed.connect(helper.on_press)
    # function returns; helper has no holder; helper freed; connection dead.

# Good — store the helper on self.
func setup_listener() -> void:
    _helper = MyHelper.new()
    button.pressed.connect(_helper.on_press)
```

This is the same lifetime trap as M5 (non-autoload nodes disconnecting in
`_exit_tree` from autoload signals): a signal connection is **not** a strong
reference to its target. **4.8.dev: confirmed** — connect a signal to a local
`RefCounted`'s method, let the local fall out of scope, then emit: the handler
does not run (`fired=false`), no error (`repro_async2_proj/` → M6). → **M6**.

### M7 — `call_deferred` runs at end of frame, not next frame

`call_deferred` does not schedule for the next frame; it schedules for the
current frame's *idle* phase, after the active call stack unwinds. Code that
assumes "deferred = next tick" misorders state changes — the deferred call may
run before a `_process` you expected to fire first. When you genuinely want
"next physics tick," use `await get_tree().physics_frame`; when you want "next
idle frame," use `await get_tree().process_frame`. **4.8.dev: confirmed** — after
`call_deferred(&"f")` the target has not run on the next line (`ran=false`); it
has run after one `await process_frame` (`ran=true`) (`repro_async2_proj/` → M7).
→ **M7**.

```gdscript
# Bad — assumes deferred = next tick. _spawn runs at end of THIS frame, before
# the next _process; code reading state "after the spawn" sees the old value.
func _process(_dt: float) -> void:
    call_deferred(&"_spawn")
    _count_spawned()               # still the OLD count — _spawn hasn't run yet

# Good — same-frame idle work stays deferred; "next tick" awaits the frame.
call_deferred(&"_spawn")           # runs after this call stack unwinds
await get_tree().process_frame     # now the deferred work has run
_count_spawned()                   # sees the new count
```

### M8 — `create_tween()` is node-bound

**In plain terms:** a tween is an animation helper. If you make it from the
node you're animating, deleting the node cleanly stops the animation. If you
make it from the whole scene instead, it keeps running after the node is gone
and tries to animate memory that no longer exists.

`create_tween()` on a `Node` creates a tween that's bound to that node's
lifetime. If the node is freed mid-tween, the tween cleanly stops. This is
usually what you want; the trap is using `SceneTree.create_tween()` from a node
context, which creates a tween bound to the whole tree — it survives the node's
freeing and may continue mutating freed memory.

```gdscript
# Bad — tween outlives the node, may target freed properties.
get_tree().create_tween().tween_property(self, "modulate:a", 0.0, 0.5)

# Good — bound to self; freed-with-self.
create_tween().tween_property(self, "modulate:a", 0.0, 0.5)
```

The `Node.create_tween()` form (which the code above relies on) is the
node-bound variant — it lives in `Node`, not `SceneTree`. **4.8.dev: confirmed,
with two nuances worth knowing** (`repro_async2_proj/` → M8). A node-bound tween
*is* invalidated when its node is freed, but (1) there's a **one-frame lag** — the
frame the node becomes invalid, `tw.is_valid()` still returns `true`; it flips to
`false` the next frame — and (2) `tw.is_running()` keeps returning `true` even
after `is_valid()` has gone `false`, so gate on `is_valid()`, not `is_running()`,
when deciding whether a tween is still alive. (Measuring this also surfaced a test
trap: an *empty* tween, with no tweener attached, is auto-killed at frame start for
an unrelated reason — give the tween real work before drawing conclusions.)
→ **M8**.

### M4 — Don't mutate a collection during iteration

Removing entries from an `Array` while iterating it skips elements and produces
inconsistent results. The standard idioms are: collect-then-delete, or iterate
in reverse.

```gdscript
# Bad — removing during forward iteration skips.
for e in enemies:
    if not e.is_alive():
        enemies.erase(e)

# Good — reverse index iteration tolerates removal.
for i: int in range(enemies.size() - 1, -1, -1):
    if not enemies[i].is_alive():
        enemies.remove_at(i)

# Or: collect then delete.
var dead: Array[Enemy] = []
for e: Enemy in enemies:
    if not e.is_alive():
        dead.append(e)
for e: Enemy in dead:
    enemies.erase(e)
```

Dictionaries have the same property — mutating keys during iteration is
undefined. **4.8.dev: confirmed** — iterating `[1,2,3,4,5,6]` and `erase(3)` when
the loop var hits `2` visits `[1,2,4,5,6]` — the element after the removed one is
skipped (`repro_typing_traps.gd` → M4). → **M4**.

### M9 — `Resource.duplicate(true)` skips `Array` contents

`Resource.duplicate(true)` was advertised as a deep copy, but it didn't recurse
into `Array` fields — sub-resources inside an `Array` stayed shared. Tracked as
[#74918](https://github.com/godotengine/godot/issues/74918); fixed in **4.5**
via a new `duplicate_deep()` method. On a target ≥ 4.5, prefer `duplicate_deep()`
when you want a true deep copy; on older targets, manually duplicate every
nested array's contents.

---

## 2f. Node method-name collisions

**In plain terms:** Godot's built-in `Node` class already owns a long list of
method names (`get_name`, `get_path`, `get_owner`, and so on). If you write a
method on your own node with the same name, you're not extending anything —
you've quietly replaced what the engine uses internally, and bits of the
engine that rely on the original will break in places far from where you
shadowed it.

`Node` has a lot of built-in methods, and shadowing one of them in a subclass
silently replaces the engine's implementation in a way that may or may not be
caught depending on the call site. The repeat offenders are `get_owner`,
`get_name`, `get_path`, `get_parent`, `get_node`, `set_owner`, `set_name`.
Define your own `get_name()` returning a `String` and you've broken every
internal Godot system that uses node names — scene saving, group lookups,
animation paths.

```gdscript
# Bad — shadows Node.get_name; breaks scene save and several internals.
func get_name() -> String:
    return _display_name

# Good — use a non-colliding name.
func display_name() -> String:
    return _display_name
```

The engine emits a warning for these collisions in modern versions, and the
linter flags them as **C9** because the failure mode is hard to debug after the
fact — the symptoms appear far from the shadowing.

The same trap exists for `Object` methods (`get`, `set`, `call`, `emit_signal`,
`has_method`) — those are even more dangerous because they're used by the
engine to drive `@export`, signals, and serialization. Treat the entire
`Object`/`Node` method surface as reserved.

→ **C9**.

---

## 2g. `@onready` and the H9 setter trap

**In plain terms:** `@onready` says "set this variable just before `_ready`
runs." If the variable has a custom setter (a small function that runs on
assignment), that setter can fire before other parts of the scene are wired
up, and reach for something that isn't there yet. Split the work: store the
raw value first, then apply it once everything is ready.

`@onready var x = …` is sugar for "assign this in `_ready` before the body
runs." If the variable has a `set` accessor, the assignment runs the setter —
and at `_ready` time, the node is in the tree but the setter may touch
not-yet-initialized siblings. Tracked as
[#71372](https://github.com/godotengine/godot/issues/71372).

```gdscript
# Bad — setter runs at _ready, touches `_label` before children are ready.
@onready var value: int = 0:
    set(v):
        value = v
        _label.text = str(v)  # _label may not be valid yet

# Good — split: cache the value, apply in _ready after children are settled.
var _value: int = 0
@onready var _label: Label = $Label

func _ready() -> void:
    _apply_value()

func set_value(v: int) -> void:
    _value = v
    _apply_value()

func _apply_value() -> void:
    if _label != null:
        _label.text = str(_value)
```

**4.8.dev (refines this):** on this build the `@onready` initial assignment does
**not** call the setter at all — it writes the field directly. Measured
(`repro_h9_proj/`): an `@onready var` with a `set(value)` accessor left the setter
**unfired** during `@onready` init (`@onready_fired_setter=false`), while a normal
later assignment did fire it (`normal_assign_fired_setter=true`, so the setter is
genuinely wired). That means the specific crash this rule warns about — the setter
running at `@onready` time and touching a not-yet-ready sibling — **can't occur on
4.8.dev**, because the setter isn't invoked then. Two caveats keep the rule alive:
(1) the inverse surprise — if you *rely* on the setter normalizing the `@onready`
value, it won't run, so the field holds the raw value; (2) older Godot versions
(pre-fix) do call it, so the split-and-apply pattern above is still the portable
shape. → **H9**.

---

## 2h. Typed math functions in hot paths

**In plain terms:** for common math like clamp/abs/max, GDScript ships two
versions — a general one that works on any number type, and a specific one
just for floats (or just for ints). The specific one skips the "what kind of
number is this?" step, so it's noticeably faster in tight loops. Match the
suffix (`f` for float, `i` for int) to the type you actually have.

The standard library has typed variants for the common math operations:
`clampf` / `absf` / `maxf` / `minf` / `floorf` / `ceilf` / `roundf` for `float`;
`clampi` / `absi` / `maxi` / `mini` for `int`. The untyped variants
(`clamp`/`abs`/`max`) force Variant dispatch on their arguments, which is a
measurable cost in a `_process` / `_physics_process` / `_draw` body.

3e measures this: in a tight loop of 2M iterations on Godot 4.8.dev,
typed `clampf`/`absf`/`maxf` came in **~1.30× faster** than the untyped
variants on float arguments. Real, ~30% in tight float loops — not enormous,
but free.

```gdscript
# Bad — untyped clamp; Variant dispatch on every call.
var t: float = clamp(elapsed / duration, 0.0, 1.0)

# Good — typed; direct float path.
var t: float = clampf(elapsed / duration, 0.0, 1.0)
```

The rule is **advisory** because a purely syntactic linter can't always tell
whether the args are `int` or `float` — `clamp(i, 0, 9)` on ints wants `clampi`,
not `clampf`. In hand-written code in `_process`/`_physics_process`/`_draw` the
discipline is mechanical: pick the variant whose suffix matches the operand
type. → **P22**.

---

## What this part is really about

If you take three things from Part II:

1. **The compiler has two instruction streams.** Stay on the typed one. H1 / H2
   / H4 / H7 / typed math functions exist because Variant dispatch is the
   dominating cost in a hot loop and you don't have to pay it.

2. **Typed collections can lie.** `.filter()` / `.map()` / `range()` return
   untyped `Array`, and direct assignment to a typed local accepts the lie
   silently. Use `assign()` (C3, C14). Typed signal parameters (H4) and typed
   Dict from JSON (H11) have the same shape — declare the type at the boundary
   and convert explicitly.

3. **`await` is a control-flow primitive, not an expression.** The function
   suspends; *anything* can happen during the suspension. Always: timeout the
   wait (M2), validate the awaited object on resume (C5), don't await in
   `_ready` (M1), don't let two coroutines race on the same signal (M3).

The async traps and the typing traps both come from the same place: a
source-level annotation or expression that *looks* like it constrains runtime
behavior, but doesn't. The discipline is to write code that doesn't depend on
those silent contracts — declare types explicitly, validate object liveness
explicitly, and assume the worst at every async boundary.
