# GDScript — Data-Oriented Design

Default paradigm. Code transforms data; doesn't *model* things. Reject three lies (Acton):

1. **Code more important than data** — wrong. Data shape determines what's possible + speed.
2. **Code models the world** — wrong. ⊥ write `Rocket` for one rocket; model `(N rockets, dt) → new positions`.
3. **Software is a platform** — wrong. Cache lines, Variant dispatch, bytecode real. Big-O ignores dominating constants.

Apply: separate **data** (POD) from **behavior** (pure transforms on collections). Encode state by **container membership**, not flags. Reference by **integer ID**, not pointer. Split data **by access pattern**, not domain object. Cheapest dispatch that fits.

## D1 — POD data, zero behavior

- `extends Resource` for saveable / editor-authored (settings, stat blocks, weapon defs, save slots).
- `extends RefCounted` for transient in-memory (events, hit results, queries, scratch records).
- Behavior moves OUT to `static func` on systems class (`CombatSystem.classify_hit(...)`) or to Node owning runtime state. `_init(...)` = constructor when field set fixed. **Don't** add `static make(...)` alongside `_init` — redundant indirection.
- **Why:** trivially serializable, diffable, mod-overridable, unit-testable (no SceneTree). Mixed data+behavior drags SceneTree into tests + tangles save format with impl.

## D2 — Existence-based processing (set membership over flags)

Optional/conditional state = entity's presence in container, not field on every entity.

| Bad | Good |
|---|---|
| `var _dead: bool` on every Enemy | `&"alive"` group |
| `poisoned_for: float = 0.0` on every Enemy | `Dictionary[NodeId, float]` keyed by poisoned only |
| `quest_giver_dialogue: String = ""` on every NPC | `&"quest_givers"` group + dialogue dict keyed by NodeId |
| `if state == ALERT and alert_timer > 0:` | iterate `&"alert"` group; entries auto-removed on expire |

Why: (1) single source of truth; (2) no flag-vs-state desync; (3) iteration naturally correct via `get_nodes_in_group(&"alive")` (cache for per-frame — see D2a below); (4) engine hooks align — `set_physics_process(false)` + `set_collision_layer(0)` at membership flip = stops ticking + stops being hit, no per-method guards.

```gdscript
# Bad — flag + guard everywhere, will desync.
var _dead: bool = false
func _physics_process(d): if _dead: return; ...
func take_damage(amt, src): if _dead or amt <= 0: return; ...

# Good — group is source of truth.
func _ready() -> void: add_to_group(&"alive")
func take_damage(amt: int, src: Node) -> void:
    if not is_alive() or amt <= 0: return
    ...
func _die(src: Node) -> void:
    remove_from_group(&"alive")
    set_physics_process(false); set_collision_layer(0)
    died.emit(src)
func is_alive() -> bool: return is_in_group(&"alive")
```

Stay bool when: binary user toggle (`_flashlight_on`), per-frame derived cache, one-shot init guard, singleton game-state (Player._dead). Multi-state machine → enum int (or one group per state). Prefer positive naming. Trap: remove-from-group ≠ SceneTree removal — visuals persist; `queue_free` still via death-visual timer.

## D2a — Groups are HashMap-backed; don't hand-roll a set "for perf"

Myth: groups = flat array scanned with `find`. False. `SceneTree` holds `HashMap<StringName, Group>`; each Node holds own `HashSet<StringName>`. Cost ([forum](https://forum.godotengine.org/t/question-about-group-does-it-iterate-over-the-whole-tree/116906)):

| Call | Backing | Cost |
|---|---|---|
| `add/remove_from_group` | HashMap insert/erase | O(1) |
| `is_in_group(&"x")` | per-node HashSet | O(1) |
| `get_first_node_in_group(&"x")` | HashMap lookup | O(1), no alloc |
| `get_nodes_in_group(&"x")` | HashMap lookup + **fresh `Array` copy** | O(k) + per-call alloc |

Only footgun: `get_nodes_in_group` in hot loop. **Need only the count → `get_node_count_in_group(group)`** — alloc-free, no `Array` copy ([proposal #7080](https://github.com/godotengine/godot-proposals/issues/7080), closed-completed/implemented; verified 2026-07). Need the members per-frame: cache + refresh on entry/exit edges (signals: `tree.node_added_to_group`, `node_removed_from_group`), or batch behind manager owning own `Array[T]`. Else: groups simplest correct shape, ⊥ replace with Dict-of-IDs "for perf."

Better than `is_in_group` when applicable: `is_in_group(&"player")` → `is Player`. Same O(1), compile-time-checked, no `StringName` hash, no typo, no tag-the-node requirement. Per-member metadata → `Dictionary[int, RecordType]` keyed by `get_instance_id()`. Groups answer "is it in set"; dicts answer "what data does it have."

Trap: hand-rolled `static var alive: Array[Enemy]` skips engine's hashset, re-implements with worse ergonomics (every spawner pushes, every `_exit_tree` pulls, forgetting one silent). Reach for group when membership genuinely tree-wide; keep local otherwise — D2b.

## D2b — Groups are a global namespace; ration like autoloads

Group registered on **whole `SceneTree`** (one process-global `HashMap<StringName, Group>`), not node or subtree. `get_nodes_in_group(&"x")` sweeps entire tree, unspecified order, fresh alloc — no subtree scope, no memory locality. So group name = **global identifier with autoload-grade hazards**: two unrelated systems both grabbing `&"active"` silently share one set; scope must be hand-encoded into string (`&"room3_enemies"`) = namespace managed by convention. Membership-not-flag (D2) unchanged; open question = *which container*, at *what scope*.

| Membership is… | Container | Why |
|---|---|---|
| tree-wide, decoupled consumers, no single owner | group `&"tag"` | engine's global registry; O(1) (D2a) |
| owned by one manager/room seeing every add+remove | that owner's typed `Array[T]` | locality, typed, save-friendly, no global name |
| per-entity data on a subset | `Dictionary[int, T]` keyed by id | answers "what data", not just "in set" |

- **Group ⇔ autoload analogy (D9):** global reach + variable membership + decoupled consumers. `&"interactable"` (raycast hits any tagged), `&"save_participants"` (save sweeps tree), HUD reading `&"boss"` without owning. That's what global registry for.
- **Single owner sees every transition → no group.** Manager that spawns+kills its enemies already *is* source of truth; its `Array[Enemy]` (refreshed inline, not via group signals) has locality tree-scattered group set can't. This = D4/D8 shape. Group there = global registry owner doesn't need.
- **Smell:** scope baked into group name (`&"room3_enemies"`, `&"team_a_alive"`) → set isn't tree-wide; belongs to whoever owns that scope. Group queried by exactly one system already holding members → drop group, hold array.

```gdscript
# Bad — tree-global group for membership one owner already sees. "Alive in THIS
# room" needs a minted &"roomN_alive" per room — namespace-by-convention.
func _ready() -> void: add_to_group(&"alive")
var here := get_tree().get_nodes_in_group(&"alive")   # every room mixed; fresh alloc

# Good — the owner holds the set: typed, scoped, local, no global name.
class_name Room extends Node
var _alive: Array[Enemy] = []
func spawn(e: Enemy) -> void: add_child(e); _alive.append(e)
func alive_count() -> int:    return _alive.size()    # O(1), this room only

# Still a group — tree-wide, owner-less, decoupled consumer (the right call):
door.add_to_group(&"interactable")                    # player raycast sweeps the tree
```

Worked example (runnable, verified 4.8.dev): `tests/example_dod_membership_proj/` + bible `ex-membership.md`.

## D3 — Reference by integer ID, not object pointer

When ref crosses systems / serialized / sits in signal payload / outlives holder's subtree → store `get_instance_id()` (or own assigned ID); resolve via `instance_from_id()` + `is`/validity check at use site.

Why: (1) an ID lookup returns the live object or `null`, **never a different object** — an engine *guarantee* in Godot 4 (39-bit validator per ObjectID, verified by source read + measurement — see [engine-bugs.md](engine-bugs.md) C8), not a workaround for the old 3.x reuse report; a raw pointer to a freed object has no such promise; (2) breaks RefCounted cycles ([#7038](https://github.com/godotengine/godot/issues/7038)); (3) save-friendly; (4) `Dictionary[int, T]` keyed by ID = natural existence-based shape; (5) external indexing without invasive bookkeeping.

```gdscript
# Bad — live ref; freed-source bug, cycle, won't serialize.
var _attacker: Node = null
func take_damage(amt: int, src: Node): _attacker = src

# Good — store ID, resolve on use.
var _attacker_id: int = 0
func take_damage(amt: int, src: Node) -> void:
    _attacker_id = src.get_instance_id() if src != null else 0
func _retaliate() -> void:
    var s: Object = instance_from_id(_attacker_id)
    if s is Enemy and s.is_alive(): ...
```

Sibling refs inside one scene tree → typed push-injection (see [style.md](style.md) M11). Child→parent → object refs fine (co-extensive lifecycle).

## D4 — Split data by access pattern, not domain object

Monolithic Enemy with 30 fields touched by 5 systems wrong. Decompose into per-concern containers:

- positions (`PackedVector3Array` on manager), AI state (typed `RefCounted` records keyed by ID), inventory (Dict keyed by item), perception (`&"alerted"` group).
- Save: `SaveSlot` = relational object — `position_data`, `inventory_data`, `quest_state`, `room_state` separate, not one blob.
- ⊥ denormalize ("cache enemy's room on enemy"). Room owns occupants; enemy looks up when needed.
- ⊥ mirror world-noun hierarchy onto class hierarchy. No `Rocket` class — `Rocket` = one row. May be `RocketDef` (Resource, shared) + `RocketPool` (Node, owns Array of active).

## D5 — Hot/cold data split

Per-frame fields shouldn't co-locate with load-time / once-per-event fields.

- Hot: position, velocity, current health, anim state, current AI state.
- Cold: max-health, damage table, dialogue strings, model path, sound IDs.
- Move cold to shared `Resource` (`EnemyDef`), one per *kind*, referenced by N runtime enemies.
- GDScript-specific: Variant boxing dominates cache effects, but every hot-loop field access still walks property table. Smaller hot objects = less per-tick overhead. Shared `EnemyDef` = N enemies of one kind share one set of design-time fields → cheaper memory + mod-overridable in one place.

## D5a — Hot-record field budget

D5 says split hot from cold. D5a = **number** that says when, plus the
field-*type* rule. Scope: `RefCounted` on **hot alloc path** — constructed
repeatedly (per-frame `Event`/`Result`, per-hit record, not-yet-pooled entity).
One-shot `Def`/config/registry entries exempt — built once, field count
free, ignore this rule.

**Measured (4.8.dev, `tests/bench_refcounted_alloc.gd` + `bench_refcounted_vartype.gd`,
N=1M, best-of-7):**

- **Methods free.** `.new()` cost flat across 0→200 methods (171→165 ns) —
  methods live on shared script, never per-instance. **Never limit method
  count for alloc reasons.**
- **Fields = whole cost,** ~linear: `cost(V) ≈ 165 + per_field·V` ns.
- **Field *type* splits two tiers** (per-var-of-type, 20 vars/class):

  | tier | types | ns/var |
  |---|---|---|
  | inline-in-Variant | int, float, bool, Vector2/3/4, Color, **Transform3D, Basis**, String `""`, StringName, object-ref, null | ~31–46 |
  | heap-backed container | `Array`, `Dictionary`, `Packed*Array`, **typed `Array[int]`** | ~75–114 |

  Line = **inline-vs-heap, not POD-vs-non-POD** — even big math structs
  (Transform3D/Basis ~46 ns) cheap; container field allocates backing
  storage per instance even when empty → 2–3×. Counterintuitive: typed
  `Array[int]` (114 ns) costs *more* to construct than untyped `Array` (75) —
  typed wins at access/iter, loses at construction.

**The budget.** 60fps frame = 16.67M ns. Holding alloc < 5% frame:

| allocs/frame | max inline fields | verdict |
|---|---|---|
| ~100 | ~170 | field count irrelevant — don't limit |
| ~1,000 | ~16 | budget bites — D5a applies |
| ~10,000 | <0 (empty already over) | must pool (P21); trimming fields won't save you |

**Rule:**

> Hot-alloc `RefCounted`: **≤ 16 fields, all inline-tier** (scalar / vector /
> color / enum-int / object-ref / String / StringName). **Zero heap-container
> members** (`Array` / `Dictionary` / `Packed*`). Methods unlimited.

Heap-container field on hot record = both 2–3× tax *and* smell: that
record carries collection owned by manager's table (D4) — move out, store
**ID** (D3) into owning container. Over budget on inline fields, or
allocating >1k/frame → hot/cold split (D5), reference-by-ID (D3), or pool (P21).
Asymmetry to remember: **fat behavior + thin data = cheap shape** —
methods cost nothing at `new()`, fields cost everything.

## D6 — Transforms over methods

Behavior = `(input data) → (output data)`. Not `data.apply_to(target)`.

```gdscript
# Bad — behavior in data class, mutates self, hard to test.
class_name HitResult extends RefCounted
var damage: int
var crit: bool
func apply(target: Enemy):
    target.health -= damage
    if crit: target.stagger()

# Good — pure transform on system; data dumb, testable in isolation.
class_name HitResult extends RefCounted
var damage: int
var crit: bool

class_name CombatSystem extends RefCounted
static func resolve(hit: HitResult, target: Enemy) -> void:
    target.health -= hit.damage
    if hit.crit: target.stagger()
```

Manager-level transforms take collections, not single items: `EnemyManager.tick_all(delta)` over `for e in enemies: e._physics_process(delta)`. Homogeneous batch → one allocator scope, branch predictor warm, cache-friendly.

## D7 — Condition tables over branch chains

Finite known dispatch keys → `Dictionary` lookup keyed by discriminator. New cases = new rows, not new code.

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

Designer-tunable → move table to `.tres` Resource (Dict export). Direct `d[k]` not `d.get(k, default)` on known schemas (S7). Doesn't apply when keys open-ended or behavior conditional on multiple non-discriminator inputs.

### D7a — Convention-derived dispatch via explicit helper

Closed enum → file path / string key mapping. Pick explicit `if/elif` helper over `Id.keys()[i].to_lower()`. Wins: no StringName alloc + lowercasing per call, one-place override for slots whose asset name diverges from enum spelling, loud default (final `else` catches new slots — pair with boot validate so missing arm surfaces there, not at first use).

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

String-literal returns interned, so dispatch cheap. Boot validate fires on missing arms via empty-return path; designer feedback at boot, not first use. Use `if/elif` for body (D7b) — value-only dispatch on `id`, not pattern matching.

## D7b — Value-only dispatch → `if/elif`, not `match`

`match` = wrong construct for value dispatch. Reserve for **actual pattern matching** (binding, destructuring, type patterns, guards). "Value-only" = branching on value of one discriminator (type code, tag byte, enum, string key) where each arm = plain compare. That = most `match` usage in wild — slower with zero offsetting benefit. **Applies even on cold paths** — construct choice unconditional; ROI just larger in hot loops.

**Bytecode:** `match` arm compiles to ~10 VM opcodes (typeof check + value compare + bool materialize + branch) — carries pattern-matching machinery (destructure, bind, type-test) even when unused. `if/elif` branch = ~2. Interpreted GDScript pays per opcode → value `match` ≈ 5× dispatch overhead of equivalent `if` chain.

> **Footnote — proposed, not shipped ([#120660](https://github.com/godotengine/godot/pull/120660), open PR, verified 2026-07):** would make compound `if` conditions *cheaper still*. Today `if a and b` materializes each operand's result into temp before branching; PR would branch directly off short-circuit → claimed ~30-35% faster for single `and`/`or`, bytecode up to 79% smaller, each extra operator costing 3 addresses not 14. **Unmerged — no shipped Godot has this. Don't tune against it.** **Does not change `if/elif` vs `match` verdict** — arms here = single compares (`if x == A`), unaffected. Only sharpens model: where arm *does* carry compound guard (`if x == A and y > 0`), `if/elif`'s lead over `match` widens, since `match`'s `when` guard sees no such optimization. One more reason value dispatch stays in `if/elif`.

**Measured** (`bench_dispatch_mechanism.gd`, 600k rows, best-of-7, median of 5 runs, all surrounding work held identical, vs `Array[Callable]` index baseline = 1.00×; absolute ratios drift ±~20% build-to-build, ordering = durable finding):

| construct | vs Callable jump-table |
|---|---|
| `Array[Callable]` index ("jump table") | 1.00× |
| `match` + direct call | 0.64× — slower than the Callable it would replace |
| `if-elif` + direct call | 1.01× |
| `if-elif` + inline read | 2.13× |
| `match`, 6 arms, hit last | 0.37× — linearity brutal |
| `if-elif`, 6 arms, hit last | 0.73× — linearity cheap |

Two takeaways: (1) no real jump table exists in interpreted GDScript — even `Array[Callable]` indexing isn't O(1)-cheap, and `match` worse than it; (2) `if/elif` lets you inline arm body (no `Callable.call`, no call frame) — where real ~2.1× win lives.

**Nuance — hoist computed subject.** `match x` evaluates `x` once; naive `if x == A: elif x == B:` re-evaluates per branch. When subject computed (`typeof(v)`, `reader.get_method()`, `outcome.value`), assign to typed local first, then branch on local:

```gdscript
var t: int = typeof(v)   # evaluate once, like match did
if t == TYPE_INT: ...
elif t == TYPE_STRING: ...
```

Plain param/local subjects need no hoist — compare directly. Don't alias param to local "to be safe"; wasted assignment.

**Nuance — order arms by likelihood.** `if/elif` = linear scan; arm k costs k compares to reach ("6 arms, hit last" row = that linearity priced). Known distribution → lead with most-frequent case: common path exits after one compare, rare arms pay the walk. Not CPU branch prediction (interpreter overhead swamps it) — average compare count. Lever `match` lacks (source-order arms, no frequency tuning). Equally-likely arms → order for readability; win only real when one case dominates.

**Nuance — `elif` vs bare `if` when every arm returns: wash, don't sweep.** Tempting theory: in a fn where each arm exits via `return`, the `elif`'s trailing jump-to-end is dead code, so a bare-`if` chain (`if k == A: return ...` / `if k == B: return ...`) should be smaller and faster. **Measured (`bench_ifchain_vs_ifelif.gd`, 4.8.dev, N=1M, 6 arms, best-of-7 × 3 runs, both hit-first-arm and hit-last-arm profiles, direct call and `Callable`): every delta inside ±1.2% and the sign flips run to run — no difference.** So this is **not** a perf lever: don't mechanically rewrite `elif` chains, and there's no lint rule (nothing to flag when two forms are equivalent). Pick on readability — `elif` signals mutual exclusivity to the reader, bare `if` reads flatter in long dispatch tables. Unchanged by this: value-only `match` → `if/elif` is still ~5× (above), and inlining the arm body still ~2.1×.

**When `match` IS still correct:** real pattern matching with no clean `if` equivalent — binding (`var n`), destructuring (`[a, b]`, `{"key": v}`), type patterns, guards (`when`), wildcard-with-binding. There expressiveness = point and perf cost buys something.

**Exhaustiveness objection — moot.** GDScript `match` does *not* enforce exhaustiveness (no compile error on missing arm), so converting value `match` to `if/elif` loses nothing safety-wise. Keep final `else`/default that fails loud (or boot-time validator), exactly as you'd keep `match`'s `_:` arm.

## D8 — Batched homogeneous processing: win is doing less, not cheaper dispatch

**Measured correction (4.8.dev, `bench_process_centralization_proj/`):** manager looping nodes and calling `e.tick()` per entity = **~2× SLOWER** than per-node `_physics_process` — GDScript method call (D9 ~4.3× tier) costs more than engine's native callback, and loop adds array overhead. Centralizing *call* = loss, not win. Dispatch win exists **only for inline SoA**: manager owning `Packed*Array`s and working them in flat loop with **no per-entity calls** (~2.3× faster at light work, tapering to parity as work grows). "One vs a few" managers: no difference.

So manager-of-Nodes earns keep by **doing less**, not cheaper dispatch:

- `EnemyManager` scene-root/autoload owns `Array[Enemy]`, `for e in alive: e.tick(delta)`, per-instance `set_physics_process(false)`. **Not** speed-up over self-ticking — value = *control* it enables (below).
- Pairs with D2: iterate alive set once/frame; dead/distant aren't in loop at all — skip + LOD (split `_alive_near`/`_alive_far`, tick far every Nth frame). **Work that doesn't happen = win.** Don't call `get_nodes_in_group(&"alive")` in loop — alloc per call; cache `Array[T]`, refresh via signals.
- For *dispatch* win, go full SoA (flat arrays, no per-entity Node) — see worked example's `EnemyManager.tick()`.
- ROI only at N × per-frame cost large enough. Don't refactor 5 enemies.

## D9 — Static-on-RefCounted vs autoload Node

Measured Godot 4.8.dev (`bench_dispatch_mechanism.gd` + `autoload_bench_proj`, best-of-7, median of 5 runs; see bible Part III §2). Absolute ratios drift ±~20% build-to-build — durable findings = **ordering** and **tiers** (instance method edges out autoload; autoload ≈ 1.1× a cached instance call regardless of absolute):

| Dispatch | × inline |
|---|---|
| inline | 1.00 |
| `static func` on `class_name`d RefCounted | ~3.3 |
| lambda `.call`, no capture | ~3.6 |
| static fn as a `Callable` (`cb = Helper.add`) | ~3.8 |
| lambda `.call`, captures a local | ~3.9 |
| instance method on cached ref | ~4.3 |
| method-ref `Callable.call` (`obj.method` as value) | ~4.7 |
| autoload global ident (`SoundBus.emit(...)`) | ~4.8 |
| lambda wrapping a named fn (`func(x): f(x)`) | ~6.5 |
| `get_node(^"AutoloadName").method()` per call | ~7.8 |
| signal_emit, 1 listener | ~7.6 |
| signal_emit, 4 listeners | ~19 |

- Pure-fn helper → `class_name FooSystem extends RefCounted` + `static func` only. Never instantiate.
- Cache/registry/RNG seed/pub-sub signal → autoload Node (must be Node to own signals).
- ⊥ resolve autoload via `get_node(^"X")` in hot paths — use global ident (cached at load).
- Promotion: static-only → drop `static`, add to `[autoload]`. Callsites unchanged (`class_name` already global).
- **Lambda dispatch**: bare lambda `.call` sits in static/instance tier (~3.6×) — fine as predicate/comparator; capturing local adds ~10%. ⊥ wrap named fn in pass-through lambda (`func(x): return f(x)`) — double-dispatch, ~6.5× vs ~3.8× to pass that same fn as `Callable` directly (real alternative), ~1.7× for nothing; pass reference (`f` / `obj.method`). Flagged **P19** (advisory). Inline-body vs extract-to-named-method perf-neutral (dead S1 rule had no perf successor) — choose on readability.

## P18 — Signals decouple, don't speed

~2× slower than static fn; scales linearly with listener count. Producer doesn't import consumers (`SoundBus.sound_emitted` → N enemy Ears subscribe).

- Hot path + small known consumer → direct call. ⊥ emit signal in `_physics_process` to one known listener (2-5× perf bug).
- Decoupled 1-N w/ variable count → signal.
- Rule: emit-freq × listener-count > 100/sec on hot path → profile first.

## Inline perf checklist (ROI-ordered)

Most dispatch cost invisible vs frame budget. Matters only in measured hot loops (1M+ ops/frame). Measure first.

| # | Move | Speedup | When |
|---|---|---|---|
| 1 | Static typing on every var/param/return | ~25-47% (workload-dep; ~1.35× typical, 4.8.dev) | always (mandatory) |
| 2 | Typed math fns (`clampf`/`absf`/`lerpf`) | ~20-30% per call | always |
| 3 | `@onready` / cached node refs (no `get_node` per call) | ~1.7× | always |
| 4 | Hoist invariants out of hot loop | linear w/ iter count | measured hot loops |
| 5 | Avoid alloc (Dict literals, `[]`/`{}`, `.new()`) in hot path | 2-10× | profiler-pointed |
| 6 | Typed RefCounted records over Dictionaries | ~2-3× field access vs key hash | cross-fn results |
| 7 | `Packed*Array` over `Array[float]`/`Array[int]` | 3-5× iter | bulk numeric |
| 8 | Hand-inline the hot body | ~3.3× (removes a static-func call, 4.8.dev) | profiler-confirmed |
| 9 | GDExtension (C++) | 10-100× | last resort |
| 10 | Tick less: skip dead, LOD the distant, cut far-tick frequency (D8) | linear w/ work cut | N × per-frame cost = bottleneck |

Trap: preemptive inlining loses reuse, hides intent, almost never moves needle. Sanity: `(call cost ns) × (calls/sec)` vs `16_600_000 ns` (60fps). < 10_000 ns → dispatch irrelevant, find another bottleneck.

## D10 — Enums over StringNames for finite closed label sets

Fixed closed set (states, kinds, slots, categories) → `enum` int. Reserve `StringName` for string-like ops (concat, prefix match) or engine APIs that demand it (`add_to_group`, `Input.is_action_*`). Enums: compile-time exhaustive in `match`, no Variant dispatch, can't typo.

**Container follows key type — preference order:**

1. **`enum` + dense `Array` indexed by enum int** (`ALL[Id.POTION]`). O(1) slot, no hash, no Variant boxing, contiguous. Default for any closed set. Enum *is* index — no separate key structure (D4 positions array, D7 condition table, D11 registry all this shape).
2. **`StringName`-keyed `Dictionary`** — only when key set genuinely open / unbounded / external (mod-supplied ids, runtime-discovered names, engine group names). `StringName` interns + compares by pointer, so beats `String` keys, but still hash lookup with Variant values.
3. **`String`-keyed `Dictionary`** — last resort. Only for keys literally text from outside (parsed JSON, file paths, user input) and never re-derived as identifier.

So: **enum + Array index > `StringName`-keyed Dict > `String`-keyed Dict.** Picking `StringName` key = admitting set not closed — if it *is* closed, enum+Array collapses lookup to bare array index and key disappears. ⊥ reach for `StringName`-keyed dict on finite known set "because it reads nicely" — that = Variant-dispatch tax (D2a, P9) for no gain.

### D10a — Type as enum at API boundaries; int at wire format

GDScript's enum = `int` under hood; passing int to enum-typed param emits warning but works. Discipline matters at **API boundary**, where designer-intent surfaces in autocomplete + code-review scrutiny:

- **Enum-typed**: registry public API (`get_def(id: Id)`), Resource fields holding a slot (`@export var id: ItemRegistry.Id`), method params receiving enum literal from known producer (`InventorySystem.consume_by_id(inv, item_id: Id, count: int)`).
- **`int`-typed**: `PackedInt32Array` (Packed* can't carry enum type), save-slot fields written to disk, return values that are *counts or indices* (`find_first → int`, `total_count → int`).

Wire format stays int because `PackedInt32Array` = only fixed-width int container — saves implicitly cast back at read. Boundary line = "is this value enum-scoped at this surface, or raw index/count?"

## D11 — Mirror registries are coupling, not split

D4 says "split data by access pattern, not domain object." Does NOT say "carry two parallel arrays keyed by same discriminator." Two registries sharing one `enum Id` as index → coupling, not split.

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

Fix one of two ways:

1. **Fold second registry into first** as derived/cached field (or method backed by ResourceLoader's own cache — see [`resource-loading.md`](resource-loading.md) "Don't roll your own cache").
2. **Derive at runtime via convention** (D7a). `Id.SWORD_GRIP` → `res://scenes/items/sword_grip.tscn`. Boot validate confirms file exists; runtime lookup = single `load()`. Parity test goes away with mirror.

Real D4 splits keep different shapes per access pattern — positions in `PackedVector3Array` on manager, AI state in `Dictionary[int, RefCounted]` keyed by id, perception via `&"alerted"` group. None duplicate index space.

Smell test: parity-asserting test checking `len(A) == len(B)` = giveaway.

---

Mechanical style/perf flags (condensed): S2 code ordering, S4 unused `_`-prefix, S5 enum iota, S6 packed `[]`, S12 print-format source, S14 `const StringName` in `find_child`, P2 value-only `match` → `if/elif` (~5× dispatch overhead, even cold paths — see D7b) ([#75682](https://github.com/godotengine/godot/issues/75682)), P3 cache autoload in hot loop, P4 fn-call overhead vs inline ([#94752](https://github.com/godotengine/godot/issues/94752)), P6 `pop_front` O(n) ([#45455](https://github.com/godotengine/godot/issues/45455)), P7 `.resize(n)` pre-alloc, P8 Dict for membership > 5 items, P20 reuse physics query objects, P21 pool > 10×/sec spawns.