# Part IV — Data-oriented design

Code transforms data; it doesn't model "things." POD records + pure transforms,
state as container membership, references by ID, schema by access pattern.

Draws from [`../rules/dod.md`](../rules/dod.md). For the rules **composed** into
runnable subsystems — strawman → data-oriented decomposition, with verified
output — see the worked examples: [combat](dod-by-example.md) (D1–D8 + P6 + C2a),
[perception](dod-perception-example.md) (existence-based state + the corrected
D8), and [inventory](dod-inventory-example.md) (D11 — one table, no mirrors).

---

## The case for DOD (even in GDScript)

Before the rules, the argument for following them. The claim: **default to
data-oriented design in Godot — not because it's fast (in GDScript the speed win
is real but muted), but because it's the cheapest path to correct, testable,
engine-aligned code, and because it's where the engine pushes you anyway the
moment you scale.**

### The default instinct is the expensive one

Open a blank script and the reflex is to model the noun: `class Enemy` with
health, position, an AI state, an inventory, a `take_damage()`, a `_die()`. One
class, one rocket. Mike Acton's framing of why that's the wrong reflex still
lands ([CppCon 2014](https://www.youtube.com/watch?v=rX0ItVEVjHc)) — the three
lies:

1. **Software is not a platform.** Cache lines, Variant dispatch, bytecode are
   real; Big-O ignores the constants that dominate a frame budget.
2. **Code does not model the world.** Don't write a `Rocket` class because the
   game has rockets. Write the transform `(N rockets, dt) → new positions` —
   that's the program; the class is a coincidence.
3. **Code is not more important than data.** The data shape decides what code is
   possible and what it costs. Pick the data shape first.

The `Enemy` class is all three at once — it models a world-noun, treats the
SceneTree as a free platform, and decides the shape of the data (30 fields, one
object, touched by five systems) as an afterthought of the code. DOD inverts the
order: data first, code as the transform `(input data) → (output data)`.

### Concede the cache argument up front — then watch it not matter

The honest objection first, because pretending it away is how you lose the
argument: **DOD's headline win is cache locality, and GDScript barely has it.**
The interpreter boxes everything in Variants; the engine's own proposal admits
"classes are not lightweight… memory is all over the place so there is not much
cache locality"
([#7329](https://github.com/godotengine/godot-proposals/issues/7329)). The
struct-of-arrays cache magic that makes C++ DOD a 10× win lives in Godot's C++
servers, not your `.gd` files.

**In plain terms:** DOD's famous speed comes from packing data tightly so the CPU
can read it in long, predictable runs (that's "cache locality"). GDScript wraps
every value in a generic box (a "Variant") and scatters objects around memory, so
that tight-packing trick mostly doesn't apply to your script code — the engine
already uses it down in its C++ rendering/physics layer, where you can't. So the
speed headline is weak in GDScript. The point of what follows: the *other*
reasons hold anyway.

So if the *only* argument for DOD were raw speed, you could fairly shrug in
GDScript. It isn't. The cache win is the least portable reason. Four survive the
trip into a managed language — three of them not about speed at all.

**1. It's the cheapest correctness, at zero entities.** The argument that doesn't
depend on scale, profiling, or the interpreter — DOD eliminates whole *bug
classes* by construction. Existence-based processing (**D2**) makes state
membership in a container, not a flag on every object: no flag to desync from
reality, because the flag *is* reality. Reference by integer ID (**D3**) returns
a live object or `null`, never a wrong-type live one — the freed-id-reuse crash
([#32383](https://github.com/godotengine/godot/issues/32383), Part I **C8**)
can't happen. Pure transforms (**D6**) test with two plain objects and no
SceneTree. A turn-based card game with nine entities gets every one of these.
DOD is correct-by-construction *before* it is fast — lead with this, it's the
claim with no counter-benchmark.

**2. The structural speed wins survive the interpreter.** Not the cache win — the
*structural* one, measured on this build (Part III): `Packed*Array` over
`Array[primitive]` (contiguous, no per-element Variant box — `S6`); one batched
manager loop over N per-node `_process` calls (a 5,000-node repro ran **14×
slower** self-processing, 93% of CPU in per-node `StringName` dispatch,
[#98175](https://github.com/godotengine/godot/issues/98175); **D8**); HashMap-
backed groups so existence-based processing is *also* the fast shape (**D2a**).
Interpreter-proof because they're about how many Variant ops happen, not cache
lines.

**3. Godot itself is data-oriented under the hood — you're following it, not
fighting it.** RenderingServer / PhysicsServer / NavigationServer operate on flat
RID handles (an RID is just an integer ticket for a thing the server owns, not a
Node object) and batched arrays; "the whole scene system is *optional*" and built
on top of them
([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)).
The engine lead, *defending* the OOP scene tree, concedes the optimization lives
in the data-oriented layer
([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
A manager owning a `PackedVector3Array` of positions does one layer up exactly
what the engine does one layer down. Alignment, not rebellion.

**4. You end up here anyway — so start here.** Part VII's escalation ladder is a
DOD on-ramp: scene tree → batched manager → `MultiMesh` → servers-direct, each
rung more data-oriented than the last (servers-direct holds 1M instances at
~160 FPS where per-node died in the thousands,
[ezcha](https://ezcha.net/news/5-16-26-rendering-a-million-objects-in-godot)). If
scale forces you there, thinking in data from the start makes the climb a
refactor of degree, not a rewrite of paradigm. Retrofitting DOD onto a graph of
fat `Enemy` objects is the expensive version.

### The "premature optimization" objection, answered

The reflexive Knuth rebuttal doesn't apply, twice over. First, **DOD is
architecture, not optimization** — Knuth's "critical 3%" is hand-tuning a hot
loop; DOD is about *which loops are possible*, and Godot's own docs draw the line:
"performant software results from performant design decisions made at the
architectural stage, before coding begins"
([general_optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)).
Second, **adoption cost ≈ zero, retrofit cost is high** — a group instead of a
bool, an ID instead of a pointer, a transform instead of a method are the same
line count to write; the desync bug, the stale-pointer crash, and the untestable
method are expensive to undo. You're declining debt, not buying speculation.

### The one concession that keeps this honest

DOD has a real failure mode, flagged as hard as the rest is advocated: **don't
normalize speculatively.** No ID-indirection for a reference that never leaves
its own subtree (a parent-owned child is a direct typed ref). No splitting one
class into five containers before a second system needs the data. No ECS-ifying
code that runs once. Three similar lines beats a premature abstraction; measure
dispatch before optimizing it (the closing rules of this part). DOD is a default
for *shape*, not a license to over-engineer — and that concession is what makes
the rest credible.

**The ask, in one line:** model the transform on N things not the thing; encode
state as membership; reference by ID across boundaries; keep behavior in pure
transforms — and you get correctness for free, speed where the interpreter still
allows it, and alignment with the engine's substrate, at no extra cost to write
and large savings not to retrofit. The cache win is a bonus you mostly collect in
C++; the rest you collect in GDScript today, at nine entities or nine thousand.

The rest of this part is those four moves as concrete rules: separate **data**
(POD) from **behavior** (pure transforms on collections); encode optional state
by **container membership**, not flags; cross-system references by **integer
ID**, not pointer; split data **by access pattern**, not domain object; cheapest
dispatch that fits.

---

## 1. POD data, pure transforms (D1, D6)

**In plain terms:** keep *what a thing is* (its fields) apart from *what you do
to it* (the code). The data class just holds values; the work happens in a
separate function that takes data in and hands data back.

A record is plain old data — fields, a constructor, nothing else. Behavior lives
elsewhere: a `static func` on a systems class, or the Node that owns the runtime
state.

```gdscript
# Bad — behavior in the data class, mutates self, hard to test.
class_name HitResult extends RefCounted
var damage: int
var crit: bool
func apply(target: Enemy):
    target.health -= damage
    if crit: target.stagger()

# Good — pure transform on a system; the data is dumb, testable in isolation.
class_name HitResult extends RefCounted
var damage: int
var crit: bool

class_name CombatSystem extends RefCounted
static func resolve(hit: HitResult, target: Enemy):
    target.health -= hit.damage
    if hit.crit: target.stagger()
```

Which base class:

- **`extends Resource`** for anything saveable or editor-authored — settings,
  stat blocks, weapon defs, save slots. Resources serialize to `.tres`, diff in
  git, hot-reload, and a designer can edit them in the Inspector.
- **`extends RefCounted`** for transient in-memory records — hit results, query
  payloads, scratch records inside a tick. They don't need a `.tres`; they
  exist for the duration of one transform and get freed when the last reference
  drops.

Two things to skip:

- **No `static make(...)` alongside `_init`.** GDScript's `_init` *is* the
  constructor. A second factory helper is redundant indirection and a place for
  the field set to drift out of sync.
- **No `func apply_to(target)` on the record itself.** That's behavior in a
  data class — pulled in to "feel object-oriented." The moment you write it,
  the test now needs a `target`, the save format now needs to round-trip
  whatever `apply_to` mutated, and the transform can no longer be tested
  without a SceneTree.

The payoff is on the *transform* side. `CombatSystem.resolve(hit, target)` is a
pure function: feed it inputs, observe outputs. The unit test is a literal
two-liner, no scene, no manager, no autoload. The save format only needs to
know how to round-trip `HitResult` fields, not how `apply_to` happened to
implement itself this week.

Manager-level transforms take *collections*, not single items. Where a per-item
`enemy._physics_process(delta)` runs the same prelude on each instance,
`EnemyManager.tick_all(delta)` iterates a typed `Array[Enemy]` once. One
allocator scope, one warm branch predictor, one cache-friendly pass. The shape
of the call matches the shape of the work. → D8, below.

---

## 2. Existence-based processing (D2, D2a)

**In plain terms:** instead of a true/false flag on every object ("is this one
dead?"), keep a *list of the ones it's true for*. Being in the list **is** the
state. Nothing to keep in sync, and you only ever loop over the ones that
matter. The textbook example is `is_dead`:

```gdscript
# Bad — flag + guard everywhere, will desync.
var _dead: bool = false
func _physics_process(d): if _dead: return; ...
func take_damage(amt, src): if _dead or amt <= 0: return; ...

# Good — group is source of truth.
func _ready(): add_to_group(&"alive")
func take_damage(amt, src):
    if not is_alive() or amt <= 0: return
    ...
func _die(src):
    remove_from_group(&"alive")
    set_physics_process(false); set_collision_layer(0)
    died.emit(src)
func is_alive() -> bool: return is_in_group(&"alive")
```

Four reasons this is better:

1. **Single source of truth.** Group membership *is* the state. There's no
   second variable to keep in sync — no `_dead = true; ... _dead = false`
   sequence to bug-fix.
2. **No flag-vs-state desync.** With the flag form, every method that depends
   on the state is one missed `if _dead:` guard away from a bug. Membership
   sidesteps the entire class of mistake.
3. **Iteration is naturally correct.** `get_nodes_in_group(&"alive")` returns
   exactly the alive set. There's no "iterate everyone then filter dead in the
   loop body" pass, and the engine doesn't need a guard inside each tick.
4. **Engine hooks align.** Flip membership and you can also
   `set_physics_process(false)` + `set_collision_layer(0)` in the same place,
   so the entity stops ticking *and* stops being hit. No per-method guards left
   to forget.

Same shape extends to per-member metadata: `poisoned_for: float = 0.0` on every
enemy becomes a `Dictionary[int, float]` keyed by the instance ID of the
poisoned subset. Only entities currently poisoned have entries; the iteration
visits only them. `quest_giver_dialogue: String = ""` on every NPC becomes a
`&"quest_givers"` group plus a dialogue dictionary keyed by NPC ID — the 99
non-quest NPCs carry zero bytes of overhead.

When to **keep a bool**:

- Binary user toggle (`_flashlight_on`).
- One-shot init guard (`_did_warmup`).
- A per-frame derived cache.
- Singleton game-state (`Player._dead` — there's only one Player, and the rest
  of the game branches on it explicitly).

Multi-state machine? An `enum int` for the current state, or one group per
state if external systems need to query "who's alerted?" cheaply. Prefer
positive naming — `&"alive"` reads as the thing you want to iterate; `&"dead"`
adds a "not" everywhere it appears.

One trap: **remove-from-group is not SceneTree removal**. The visual stays in
the scene; the entity stays at its position. `queue_free` is still the right
move once any death-visual timer has elapsed.

### Groups are HashMap-backed (D2a)

The reflex objection is "but groups are an array scan, surely a Dict is
faster." That's folklore. Godot's `SceneTree` holds a
`HashMap<StringName, Group>`; each Node holds its own `HashSet<StringName>`.
The cost table ([forum
thread](https://forum.godotengine.org/t/question-about-group-does-it-iterate-over-the-whole-tree/116906)):

Measured on Godot 4.8.dev (`bench_group_ops.gd`):

| Call | Backing | Cost | Measured |
|---|---|---|---|
| `add/remove_from_group` | HashMap insert/erase | O(1) | ~55 ns / add+remove pair |
| `is_in_group(&"x")` | per-node HashSet | O(1) | ~23 ns/call |
| `get_first_node_in_group(&"x")` | HashMap lookup | O(1), no alloc | ~34 ns/call |
| `get_nodes_in_group(&"x")` | HashMap lookup + **fresh `Array` copy** | O(k) + per-call alloc | ~7.6× a cached-array read (group of 200) |

The measured numbers confirm the shape: membership tests are tens of nanoseconds —
nothing. The only real footgun is the last row: `get_nodes_in_group` allocates a
fresh `Array` on every call (it has to — it can't hand you its internal storage),
so in this bench it ran **~7.6× slower** than iterating a cached array, and the gap
grows with group size. Calling it inside a per-frame loop is exactly the "alloc in
a hot path" anti-pattern Part III warns about ([proposal
#7080](https://github.com/godotengine/godot-proposals/issues/7080)). The fix is to
cache the array on the manager side and refresh it via the
`tree.node_added_to_group` / `tree.node_removed_from_group` signals on the group's
entry/exit edges. Everything else — membership tests, single-entity lookups, the
membership flip on death — is O(1), and groups are the simplest correct shape.

**In plain terms:** asking "is this node in the set?" is cheap — it's a hash
lookup, like checking a key in a dictionary. Asking "give me *everyone* in the
set" is what costs, because the engine has to build you a brand-new list each time.
Do that once and keep the list; don't ask again every frame.

One refinement: **when the group corresponds to a class, prefer `is`.**

```gdscript
# Both O(1) — but the right-hand form is compile-time-checked.
if collider.is_in_group(&"player"): ...
if collider is Player: ...
```

`is Player` measured **identical** to `is_in_group(&"player")` (1.00× in
`bench_group_ops.gd` — the interned `StringName` makes the hash effectively free),
so this is not a speed choice: pick `is` because it's compile-time-checked — no
typo risk, and no requirement that someone remembered to
`add_to_group(&"player")` in `_ready`. The class system *is* the membership test.
Groups are for sets that don't correspond to a class (`&"alive"`, `&"alerted"`,
`&"quest_givers"`).

And the hand-rolled alternative — `static var alive: Array[Enemy]`, push from
`_ready`, pull from `_exit_tree` — re-implements the HashMap with worse
ergonomics: every spawner has to remember the push, every death path has to
remember the pull, and forgetting one is silent corruption. Default to groups;
roll your own only when you need typed storage or save-side serialization.

---

## 3. References by integer ID (D3)

**In plain terms:** when you need to remember *another* object that might get
deleted out from under you, don't hold the object — hold its ID number, and look
it up when you actually need it. The lookup gives you the live object or
nothing; it can never hand you the wrong object.

Store `get_instance_id()` (or your own ID) and resolve via `instance_from_id()`
+ a validity check at the use site when a reference *crosses systems*, *gets
serialized*, *sits in a signal payload*, or *outlives the holder's subtree*.

```gdscript
# Bad — live ref; freed-source bug, cycle, won't serialize.
var _attacker: Node = null
func take_damage(amt: int, src: Node): _attacker = src

# Good — store ID, resolve on use.
var _attacker_id: int = 0
func take_damage(amt: int, src: Node):
    _attacker_id = src.get_instance_id() if src != null else 0
func _retaliate():
    var s: Object = instance_from_id(_attacker_id)
    if s is Enemy and s.is_alive(): ...
```

Five things this buys:

1. **Sidesteps the freed-ID-reuse bug**
   ([#32383](https://github.com/godotengine/godot/issues/32383)). With a live
   ref, Godot can recycle the slot to a different object and your "still
   valid" check passes against the wrong instance. `instance_from_id` returns
   the live object *or* `null` — never a wrong-type live object.
2. **Breaks RefCounted cycles**
   ([#7038](https://github.com/godotengine/godot/issues/7038)). Two RefCounteds
   pointing at each other leak silently. IDs are integers; integers don't form
   cycles.
3. **Save-friendly.** An ID is an int. A live `Node` ref is not, and you can't
   round-trip it through `var_to_str` / `JSON.stringify`.
4. **Existence-based shape falls out for free.** `Dictionary[int, T]` keyed by
   ID is the natural per-subset container — see §2.
5. **External indexing without invasive bookkeeping.** A combat log keyed by
   attacker ID doesn't need every potential attacker to register itself
   anywhere; the IDs are already there.

When **object refs stay correct**:

- **Sibling refs inside one scene tree.** Wire them by typed push-injection
  from the scene-root script (see `style.md` M11). Their lifecycle is
  co-extensive with the parent, so there's no "outlived" case to worry about.
- **Child → parent.** Same reasoning: the child can't outlive the parent.

The line is *lifetime coupling*. If you can prove the reference will be freed
no later than the holder, use the typed pointer — it's faster, narrows the
type, and reads cleaner. If you can't prove it, use the ID.

---

## 4. Split by access pattern, not domain object (D4)

**In plain terms:** don't put all 30 of an enemy's fields in one `Enemy` class
just because "an enemy is one thing." Group fields by *which system uses them* —
positions where the physics loop wants them, AI state where the AI loop wants
it. The entity's ID number is the thread that ties the pieces back together.

A monolithic `Enemy` with thirty fields touched by five systems is the wrong
shape — each system reads its own subset, most fields cold to most callers.
Decompose along the *access pattern*, not the imaginary domain object.

A worked example:

- **Positions** — `PackedVector3Array` on the manager. The physics loop reads
  all of them in order; cache-warm, no per-instance dispatch.
- **AI state** — typed `RefCounted` records keyed by ID in a
  `Dictionary[int, AIRecord]`. Only entities currently *running* an AI
  decision tree have entries.
- **Inventory** — a `Dictionary[int, Array[ItemRecord]]` keyed by entity ID.
  Most NPCs don't have one; they don't have an entry.
- **Perception** — `&"alerted"` group. Membership *is* the state (see §2).

The save format inherits the same split. A `SaveSlot` is **relational**:
`position_data`, `inventory_data`, `quest_state`, `room_state` — separate
fields with their own schemas, not one opaque blob. When you add a new
subsystem, it adds a new field; it doesn't reshape the existing ones.

Two anti-patterns:

- **Denormalization.** "Cache the enemy's current room on the enemy" sounds
  like a perf win, but it makes the room → occupants relationship double-edged:
  every move now has to update both sides, and forgetting either side is
  silent. The room owns its occupant list; the enemy looks up by room ID when
  it actually needs to.
- **Mirroring the world's noun hierarchy onto the class hierarchy.** There is
  no `Rocket` class because there is no one "rocket" in the program. There may
  be a `RocketDef` (a `Resource`, shared across all rockets of one kind) and a
  `RocketPool` (a `Node` that owns an `Array` of active rocket *rows*). The
  individual rocket is a row, not a class.

The discipline question to ask before writing a class: *which transforms read
or write these fields, at what rate?* If two transforms touch disjoint subsets,
they're two different access patterns and the data wants to be split.

---

## 5. Hot/cold split (D5)

**In plain terms:** the values that change every frame (position, health) should
live apart from the values fixed for a whole *kind* of thing (max health, model,
sounds). Put the fixed stuff in one shared `EnemyDef` that all enemies of that
kind point at — one copy, editable in one place — instead of repeating it on
every instance.

Within the data you do keep together, per-frame fields should not co-locate with
load-time fields.

- **Hot** — position, velocity, current health, current animation state,
  current AI state.
- **Cold** — max health, damage table, dialogue strings, model path, sound
  IDs, "what kind of enemy is this."

The move is to factor the cold fields into a shared `Resource` (`EnemyDef`)
referenced by N runtime instances of one kind. The hot instance carries a
pointer to its def; the def's fields are read once at spawn (or on demand) and
otherwise sit on disk-cache pages the hot loop never touches.

In a cache-coherent language (C++, Rust, GDExtension) the win is the cache: a
smaller hot struct fits more entities per cache line, the cold fields never
evict the hot ones. In interpreted GDScript the cache effects are real but
dominated by Variant boxing and bytecode overhead — the bigger win is per-tick
*property table walks* through fewer fields, and the modding/balance win of
having every per-kind constant in one shared `.tres` a designer can edit.

The structural test is: **if I added a tenth enemy kind tomorrow, where would
the new fields go?** If the answer is "edit the runtime `Enemy` class," cold
data is in the wrong place — it should be a new `EnemyDef.tres`.

---

## 6. Condition tables over branch chains (D7)

**In plain terms:** when you have a long `if/elif` that just maps one fixed set
of inputs to outputs, make it a lookup table instead. Adding a case becomes
adding a row of *data* — nobody has to touch the function, and a designer can
even tune it from a `.tres`.

Finite, known dispatch keys → a `Dictionary` lookup keyed by the discriminator.

```gdscript
# Bad — every (weapon, armor) edits this fn.
func damage_multiplier(w: int, a: int) -> float:
    if w == W.PISTOL and a == A.NONE: return 1.0
    if w == W.PISTOL and a == A.LIGHT: return 0.8
    if w == W.SHOTGUN and a == A.NONE: return 1.5
    ...

# Good — table is data.
const DAMAGE_MULT: Dictionary = {
    W.PISTOL:  {A.NONE: 1.0, A.LIGHT: 0.8, A.HEAVY: 0.5},
    W.SHOTGUN: {A.NONE: 1.5, A.LIGHT: 1.1, A.HEAVY: 0.7},
}
func damage_multiplier(w: int, a: int) -> float: return DAMAGE_MULT[w][a]
```

What this gets you:

- **The dispatch is data**, not branches in a function. A designer adding a
  new weapon edits the table; nobody touches `damage_multiplier`.
- **Move the table to a `.tres`** the moment a designer needs to tune it from
  the Inspector. The function signature does not change; the source of the
  data does.
- **Direct subscript `d[k]`**, not `.get(k, default)`. On a known schema, the
  key is always present — the `.get` form is defensive code that hides
  contract violations (S7).

When this doesn't apply: keys open-ended (user-supplied tag strings,
externally-named events), or behavior conditional on multiple non-discriminator
inputs (the cell value isn't just a number — it's a `(value, animation, sound)`
triple, at which point an `if/elif` body is fine).

### Convention-derived dispatch (D7a)

A common subcase: closed enum → file path or string key. The naive form
allocates and disallows per-slot overrides:

```gdscript
# Bad — alloc per call; can't override a slot whose .tscn diverges
# from the enum name without renaming the enum.
func _scene_path(id: Id) -> String:
    return "res://scenes/items/%s.tscn" % Id.keys()[id].to_lower()

# Good — allocation-free, per-slot override at hand. if/elif not match (D7b).
static func _scene_basename(id: Id) -> String:
    if id == Id.POTION: return "potion"
    elif id == Id.SWORD_GRIP: return "sword_grip"
    ...
    else: return ""   # inventory-only / unmapped
```

Three wins over the `Id.keys()[i].to_lower()` form:

1. **No `StringName` allocation per call**, no lowercasing pass. The
   string-literal returns are interned.
2. **One-place override** when a slot's asset basename has to diverge from the
   enum spelling (`Id.SWORD_GRIP` → `"sword_pommel"` if the designer renamed
   the file). You don't have to rename the enum to match the file.
3. **Loud default.** The final `else` is the catch for new enum members. Pair
   it with a boot-time validator (Part V) and a missing arm crashes at boot,
   not at first use.

Use `if/elif` for the body — value-only dispatch on `id`, not pattern matching
(D7b, below).

### Value-only dispatch → `if/elif`, not `match` (D7b)

This is the place where data-oriented design and Part III converge directly.
The measured numbers (`bench_dispatch_mechanism.gd`, 600k rows, best-of-7,
Godot 4.8.dev; baseline = `Array[Callable]` table = 1.00×) live in
[Part III §1](03-performance.md#1-dispatch--match-vs-ifelif-vs-a-callable-table)
in full. The short version: a value-only `match` is the *slowest* dispatch in
GDScript, slower even than the `Array[Callable]` table it would replace
(0.67× at 3 arms, 0.41× at 6).

The mechanism: a `match` arm carries pattern-matching machinery — type check,
value compare, destructure, bind — even when you use none of it, and the arms
are scanned in order, so it degrades as the matched arm moves later. An
`if/elif` chain skips that machinery, and — the part that matters — lets you
*inline the arm body*, dropping the `Callable.call` and the call frame on top.
That inlining is where the win lives: an inlined `if/elif` runs ~2.4× the
throughput of the `Callable` table, the only construct measured that beats it.

The construct choice is unconditional: it applies on cold paths too, because
it's not a perf-only argument. `match`'s pattern-matching machinery isn't
buying anything when the arms are plain compares — and a `match` of value
literals reads as a `switch` to a reviewer who then has to remember that
GDScript's `match` is *not* `switch`. Use it where the expressiveness is the
point.

**Nuance — hoist a computed subject.** `match x` evaluates `x` once; a naive
`if x == A: elif x == B:` re-evaluates per branch. When the subject is computed
(`typeof(v)`, `reader.get_method()`, `outcome.value`), assign to a typed local
first:

```gdscript
var t: int = typeof(v)   # evaluate once, like match did
if t == TYPE_INT: ...
elif t == TYPE_STRING: ...
```

Plain param/local subjects need no hoist — compare directly. Don't alias a
param to a local "to be safe"; that's a wasted assignment.

**When `match` *is* still correct:** real pattern matching with no clean `if`
equivalent — binding (`var n`), destructuring (`[a, b]`, `{"k": v}`), type
patterns, guards (`when`), wildcard-with-binding. There the expressiveness is
the point and the per-arm cost buys something. Reserve `match` for that and
nothing else.

**Exhaustiveness objection — moot.** GDScript `match` does *not* enforce
exhaustiveness (no compile error on a missing arm), so converting a value
`match` to `if/elif` loses nothing safety-wise. Keep a final `else` that fails
loud (or a boot-time validator), exactly as you'd keep `match`'s `_:` arm.

---

## 7. Batched homogeneous processing over per-Node ticks (D8)

**In plain terms:** the instinct is "one manager looping the entities must beat N
entities each ticking themselves." Measured, that's only true if the manager
stops calling a *method per entity* — a GDScript method call costs about as much
as the engine's own per-node callback, so looping and calling `e.tick()` buys
nothing and loses to the array overhead. The real win is twofold: tick *fewer*
things (skip the dead and distant), and where it's hot, work *flat data* in one
pass instead of calling N objects.

**4.8.dev: measured, and it overturns the naive claim**
(`bench_process_centralization_proj/`, ordering-bias-controlled; full table +
correction note in `tests/BENCH.md`). Baseline = per-node `_physics_process` =
1.00× (higher = faster):

| Layout | W=0 (pure dispatch) | W=30 (light work) |
|---|---|---|
| per-node `_physics_process` | 1.00× | 1.00× |
| one (or four) managers looping nodes, calling `e.tick()` | **~0.47×** | ~0.50× |
| **inline manager** — flat `PackedInt32Array`, no per-entity calls | **~2.3×** | ~1.1× |

Two surprises:

- **A manager looping nodes and calling `e.tick()` per entity is ~2× SLOWER than
  letting them self-process.** A GDScript instance-method call is the
  ~5.3×-inline tier of §8's ladder; the engine's native `_physics_process`
  dispatch is cheaper. You pay N calls either way, and the loop adds array
  iteration on top. (This corrects an earlier toggle-in-one-scene repro that
  reported a slight manager *win* — an A/B-ordering artifact; see BENCH.md.)
- **Eliminating the per-entity call is the win.** An inline manager that owns a
  flat array and works it in place — no `Enemy` objects, no `e.tick()` — runs
  2.3× faster than per-node when work is light (dispatch is the whole cost),
  tapering toward parity as per-entity work grows. "One vs a few" managers: no
  difference.

So D8 is really two claims, and only one is about dispatch speed. The fast form
is **SoA**, the shape §4 already pushes: state in manager-owned `Packed*Array`s,
the tick a flat loop over indices with no per-slot method call (the worked
example's `EnemyManager.tick()` is exactly this). The form below — a manager
looping `Enemy` nodes — does **not** win on dispatch:

```gdscript
class_name EnemyManager extends Node

var _alive: Array[Enemy] = []           # cache, refreshed via group signals

func _physics_process(delta: float) -> void:
    for e: Enemy in _alive:             # typed for (H2)
        e.tick(delta)                   # ← a method call per entity: measured
                                        #   ~2× SLOWER than per-node, not faster
```

Its value is **not** dispatch speed — it's the control §2 buys. `_alive` already
excludes the dead, and you can split `_alive_near` / `_alive_far` and tick the
far group every Nth frame. **The work that doesn't happen is the cheapest work in
the program** — and *that*, not a cheaper loop, is why a manager earns its keep
while the entities stay Nodes. Each enemy `set_physics_process(false)` in `_ready`
so only the manager drives them: necessary for the control, even though the loop
itself isn't the speed-up. If you need the dispatch win too, drop the per-entity
Node and go SoA.

Two things to watch:

- **Don't call `get_nodes_in_group(&"alive")` inside the per-frame loop.** It
  allocates a fresh array on every call (D2a). Cache the typed `Array[Enemy]`
  on the manager and refresh it on the two edge signals.
- **Getting the dead *out* of the manager's list** has its own measured answer:
  swap-back for a single removal, write-cursor *compaction* for culling a whole
  subset (it beats repeated swap-back and keeps order), never `remove_at` in a
  loop. See [removing dead entities](removing-dead-entities.md).
- **The dispatch win is in SoA, not the loop.** Don't reach for a manager-of-nodes
  *for speed* — it's a loss. Reach for it for control (skip/LOD), or go full SoA
  for the speed. And measure first: Part III's heuristic, `(call cost ns) ×
  (calls/sec)` vs `16,600,000 ns` (one 60 fps frame); under ~10,000 ns of frame
  budget, none of this is your bottleneck.

The control shape makes higher-level moves possible: sort `_alive` by distance
once per second and deep-tick only the first N; split into two arrays and tick the
far one every other frame. None of that is expressible against per-Node
`_physics_process` — all of it is one loop's distance away once the manager owns
the set.

---

## 8. Dispatch — static, autoload, signal (D9, P18)

**In plain terms:** there are several ways to call a helper, and they cost
different amounts. Cheapest is a `static func` on a `class_name`'d class.
Autoloads and signals cost more — use them for what they're *for* (shared state,
decoupling), not because they're convenient.

When a helper is stateless, the cheapest dispatch is a `static func` on a
`class_name`'d RefCounted. The full cost ladder is in
[Part III §2](03-performance.md#2-call-overhead--indirection) — the relevant
lines, baseline = inlined expression = 1.00×:

| Path | × inline |
|---|---|
| inlined expression | 1.00 |
| `static func` on a `class_name`'d RefCounted | ~4.1 |
| instance method on a cached ref | ~5.3 |
| autoload global identifier (`Bus.method()`) | ~5.7 |
| `get_node(^"X").method()` per call | ~9.8 |
| `signal.emit()`, 1 listener | ~9.5 |
| `signal.emit()`, 4 listeners | ~23 |

(The autoload row is measured in its own project, `tests/autoload_bench_proj/`,
against the same inline baseline — autoload globals only exist when a real project
registers an `[autoload]`. It lands just above the instance-method tier: calling a
method on a globally-resolved singleton.)

Rules of thumb:

- **Pure-fn helper → `class_name FooSystem extends RefCounted` + `static func`
  only** (~4.1×, the cheapest indirection measured). Never instantiate; you don't
  want the call-site to drift to `FooSystem.new().method(...)` (~5.3×). `_init`
  doesn't exist on a class you never construct.
- **Stateful (cache, registry, RNG seed, pub-sub signal) → autoload Node.**
  Signals require a Node owner; mutable shared state wants a clear lifecycle.
- **Never resolve an autoload via `get_node(^"X")` in a hot path.** The autoload's
  name is a *global identifier* (~5.7× inline); use it directly. Going through
  `get_node()` instead is ~9.8× inline — about ~1.7× the cost of the global ident,
  because it walks the scene tree by name every call. → P3.
- **Promotion path: static-only → autoload Node** is a one-line change. Drop
  `static`, add the `[autoload]` entry. Callsites unchanged because the
  `class_name` was already a global identifier.

### Signals decouple, they don't speed (P18)

A signal emit is roughly 2× a static call to start, and the cost scales
linearly with the listener count. The point of a signal is **decoupling** —
the producer doesn't have to import the consumer set; consumers subscribe and
unsubscribe independently. That's a real, valuable architectural property. It
isn't a *performance* property.

Concretely:

- **Hot path + small known consumer → direct call.** Emitting a signal in
  `_physics_process` to one known listener is a 2–5× perf bug dressed as
  architecture.
- **Decoupled 1-to-N with variable count → signal.** This is what signals are
  for: a producer (`SoundBus.sound_played`) that doesn't know or care which
  enemy `Ears` are listening.
- **Rule of thumb:** if emit-frequency × listener-count exceeds 100/sec on a
  hot path, profile before committing. Otherwise the dispatch cost is below
  the noise floor.

---

## 9. Enums vs StringNames at API boundaries (D10, D10a)

**In plain terms:** for a fixed list of named options (states, item kinds), use
an `enum` — it's an integer the compiler checks, so a typo won't compile. Use
`StringName` only for text-like work or engine calls that demand it. Enums
compare as ints, never silently pass a misspelling.

Reserve `StringName` for string-like ops (concat, prefix match) or engine APIs
that demand it (`add_to_group`, `Input.is_action_*`).

The enum wins are layered:

- **No `StringName` hash on every comparison.** An `enum` arm is an int
  compare; a `StringName` arm is a hash compare.
- **No typo silently passing.** `Id.SWORD_GRIP` is a compile-time identifier.
  `&"sword_gripp"` is a string literal; the typo is a no-op until the dispatch
  silently fails.
- **No Variant dispatch** through a `StringName`-keyed `Dictionary` when an
  `enum` index into an array would do.

### Type as enum at API boundaries; int at wire format (D10a)

GDScript's enum is `int` under the hood — passing an int to an enum-typed
param emits a warning but works. So the discipline matters at the **API
boundary**, where designer-intent surfaces in autocomplete and code review:

- **Enum-typed:**
  - registry public API (`get_def(id: Id)`),
  - Resource fields holding a slot (`@export var id: ItemRegistry.Id`),
  - method params receiving an enum literal from a known producer
    (`InventorySystem.consume_by_id(inv, item_id: Id, count: int)`).

- **`int`-typed:**
  - `PackedInt32Array` (the Packed\* variants can't carry an enum type),
  - save-slot fields written to disk,
  - return values that are *counts or indices* (`find_first → int`,
    `total_count → int`).

The wire format stays `int` because `PackedInt32Array` is the only fixed-width
int container — saves implicitly cast back at read time. The boundary line is
"is this value enum-scoped at *this* surface, or is it a raw index or count?"
Once that line is clear, the warnings GDScript emits at int↔enum crossings
become meaningful: every warning at that boundary either gets a deliberate
cast or a corrected type, and warnings at non-boundary sites are bugs.

---

## 10. Mirror registries are coupling, not split (D11)

**In plain terms:** don't keep two lists that must stay the same length, lined
up by the same index. That's not "splitting data" — it's storing one fact twice,
and now every change has to touch both. The tell is a test that checks the two
lists are the same size.

§4 says "split by access pattern, not domain object." It does **not** mean
"carry two parallel arrays keyed by the same `enum Id`" — that's coupling
expressed as two files.

```gdscript
# Bad — parallel arrays must stay length-aligned. Every new item edits
# both arrays + a parity test guards the drift.
class_name ItemRegistry
static var ALL: Array[ItemDef] = [null, preload(...), ...]   # the data

class_name DropRegistry           # second autoload, parallel array
static var SCENES: Array[PackedScene] = [null, preload(...), ...]

# Parity-asserting test = the smell:
assert_eq(DropRegistry.SCENES.size(), ItemRegistry.Id.size())
```

Two fixes:

1. **Fold the second registry into the first** as a derived/cached field, or
   a method backed by `ResourceLoader`'s own cache (see
   [`../rules/resource-loading.md`](../rules/resource-loading.md) — "Don't roll
   your own cache"). `ItemDef` grows a `pickup_scene` field; the parallel
   array goes away.
2. **Derive at runtime via convention** (D7a). `Id.SWORD_GRIP` →
   `res://scenes/items/sword_grip.tscn`. Boot validate confirms the file
   exists; the runtime lookup is a single `load()`. The mirror — and the
   parity test that was guarding it — both go away.

Real D4 splits keep **different shapes per access pattern**: positions in
`PackedVector3Array` on a manager, AI state in `Dictionary[int, RefCounted]`
keyed by ID, perception via `&"alerted"` group. None of them duplicate the
index space; each one is the shape its access pattern wants.

The smell test is sharp: **a parity-asserting test that checks
`len(A) == len(B)`** is the giveaway. The test exists because two structures
must agree, which means they encode the same fact twice. Fold one into the
other, derive one from convention, or accept that you're paying for the
coupling forever.

---

## The discipline, condensed

Five moves in one place:

1. **Data is POD; behavior is transform.** Data classes carry fields and a
   constructor. Pure functions on a `class_name`'d systems class do the work.
2. **State is membership, not a flag.** Group, dictionary, or array
   membership — single source of truth, iteration naturally correct, engine
   hooks line up.
3. **Cross-system references are IDs.** `get_instance_id()` in, validity check
   at use site. Sibling and child→parent refs can stay typed.
4. **Split by access pattern, not domain object.** Decompose monolithic
   classes along the lines of which transforms read or write which fields.
5. **Cheapest dispatch that fits.** Inline the body when you can; `if/elif`
   when you must branch; `static func` over autoload over instance method
   over `get_node()` per call; signal only when 1-to-N variable-count
   decoupling is the *point*.

The throughline is the same one Part III labors: **the data shape decides
what's possible and what it costs.** Pick the shape first.
