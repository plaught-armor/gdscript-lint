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

## 1. Static typing is the single biggest perf win

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
[Part III §5](03-performance.md#5-static-typing--the-things-that-are-not-faster).

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

## 2. Typed-collection traps

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
on Godot 4.8.dev (see [Part I §4](01-engine-bugs.md#4-typed-filter--map-return-untyped-array)):
`.filter()` now returns a *typed* result — fixed — but `.map()` still returns an
untyped `Array`.** Until your minimum Godot has both fixed, keep the `assign()`
habit for both; it's harmless on the already-fixed `.filter()` path. → lint rule
**C3** (engine bug, blocking).

### C14 — `range()` produces untyped Array

`range(N)` returns `Array` (untyped). Assigning the result to `Array[int]`
silently produces an untyped collection. This is a typing bug, not a loop-speed
bug — iteration over `for i in range(N)` is fine (Part III §3 measures it as
break-even with `for i: int in N`); the breakage is at the *assignment*:

```gdscript
# Bad — silently untyped despite the annotation.
var indices: Array[int] = range(10)

# Good — explicit construct.
var indices: Array[int] = []
indices.assign(range(10))
```

Tracked as [#110659](https://github.com/godotengine/godot/issues/110659). →
**C14**.

### H10b — Type the container, don't probe it

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

### H14 / H14b — No redundant `as` after `is`, no `as` after typed access

`if x is T:` already narrows `x` inside the branch — a follow-up `(x as T).member`
is a Variant round-trip that produces the type the compiler already had.
Likewise, typed-container access is already typed: `Dictionary[K, V].get(k)`,
`dict[k]`, `Array[T][i]` all return typed `V`/`T`. Re-casting with `as T` is the
same wasted round-trip.

```gdscript
# Bad — `x` is already T inside the branch; `as` round-trips.
if x is Enemy:
    (x as Enemy).take_damage(5)

# Good.
if x is Enemy:
    x.take_damage(5)

# Bad — `_cells.get(path)` already returns CellState.
var cs: CellState = _cells.get(path) as CellState

# Good.
var cs: CellState = _cells.get(path)
```

Containers carry their type — trust them. → **H14**, **H14b**.

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

`@export var def: ItemDef` doesn't get a default-constructed `ItemDef` — it
defaults to `null`, and any code that touches `def.field` before the editor
assigns one will crash with a "Cannot access property on null instance" error.
Tracked as [#110394](https://github.com/godotengine/godot/issues/110394) (fixed
**4.6**). On a Godot ≥ 4.6 target this is no longer a runtime trap, but a boot
validator that errors on a still-null `@export` is still the right discipline —
the failure surfaces at the editor boundary instead of at first use. See
`style.md` M10 / M10a.

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

### H3 — Enums are an `int` at runtime; type the boundary

GDScript enums are `int` under the hood. The compiler will accept a bare `int`
where an enum-typed parameter is declared (it emits a warning, but it works).
The discipline is: at API boundaries, declare the enum type — registry public
methods, `@export var slot: ItemRegistry.Id`, signal parameters. Inside hot
loops or save-format fields, `int` is the right choice (`PackedInt32Array` can't
carry an enum type; save slots round-trip as `int`). This is covered in detail
in [`../rules/dod.md`](../rules/dod.md) D10/D10a. **4.8.dev: confirmed** —
`typeof(SomeEnum.MEMBER) == TYPE_INT` (`repro_typing_traps.gd` → H3).

---

## 3. Lambdas and capture semantics

Lambdas are useful in GDScript, but their interaction with the formatter and
with capture semantics is the source of two reliable foot-guns.

### S1 — No inline lambdas (the formatter breaks them)

`gdscript-formatter` doesn't reliably preserve indentation inside an inline
lambda. The function runs correctly; the formatted file looks like the lambda
body is at the wrong nesting level, and the next person to read it (or the next
review tool) treats it as a bug. The deterministic fix is to extract the body
to a named method:

```gdscript
# Bad — formatter will rearrange the indentation, making this hard to read.
queue.filter(func(p):
    if not is_instance_valid(p):
        return false
    return p.is_alive() and p.faction != self.faction
)

# Good — extracted, formatter-stable, also testable.
result.assign(queue.filter(_is_hostile_alive))

func _is_hostile_alive(p: BattlePawn) -> bool:
    if not is_instance_valid(p):
        return false
    return p.is_alive() and p.faction != faction
```

Trivial single-expression lambdas (`func(x): return x.id`) are not the target —
the rule fires on multi-statement bodies that the formatter can't reliably
reflow. → **S1**.

### H6 — Capture by-value for locals, by-ref for members

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
arr.for_each(func(item):
    _count += 1
)
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

## 4. `await` and coroutines

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

### M8 — `create_tween()` is node-bound

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
for i in range(enemies.size() - 1, -1, -1):
    if not enemies[i].is_alive():
        enemies.remove_at(i)

# Or: collect then delete.
var dead: Array[Enemy] = []
for e in enemies:
    if not e.is_alive():
        dead.append(e)
for e in dead:
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

## 5. Node method-name collisions

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

## 6. `@onready` and the H9 setter trap

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

→ **H9**.

---

## 7. Typed math functions in hot paths

The standard library has typed variants for the common math operations:
`clampf` / `absf` / `maxf` / `minf` / `floorf` / `ceilf` / `roundf` for `float`;
`clampi` / `absi` / `maxi` / `mini` for `int`. The untyped variants
(`clamp`/`abs`/`max`) force Variant dispatch on their arguments, which is a
measurable cost in a `_process` / `_physics_process` / `_draw` body.

Part III §4 measures this: in a tight loop of 2M iterations on Godot 4.8.dev,
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
