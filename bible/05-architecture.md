# Part V — Architecture

Where things live. A cross-project skeleton, a fixed set of canonical autoloads,
and a decision rubric for the questions that come up on every Godot project:
"where does X go?", "what shape should this be?", "do I need an autoload here?"

This part is more prescriptive than the rest of the Bible. The performance and
engine-bug chapters report what the engine does; this one reports a default
*shape* — the layout that drops in cleanly on a new project and stops you
re-litigating dir naming on every commit. It is the default, not the
prescription. The closing section names the cases where you should break it.

Draws from [`../rules/architecture.md`](../rules/architecture.md).

**In plain terms:** this part is a starter floor plan for a Godot project. It
says where each kind of file goes, which globals every project ends up needing,
and what to name things — so you stop re-deciding the same questions on every
new project.

---

## 5a. Directory layout

**In plain terms:** a fixed set of folders, each with one job. Data files
(designer-tunable) sit in `resources/`; code sits in `scripts/`; scenes sit in
`scenes/`. Keeping data and code in separate folders prevents the cyclic
references that cause some nasty engine bugs.

```
project_root/
├── project.godot
├── autoloads/          # singleton .gd files (Node-derived)
├── scenes/             # *.tscn — leaves of dependency graph
│   ├── items/          # pickup scenes, all inherit _pickup_base.tscn
│   ├── enemies/
│   ├── rooms/
│   └── ui/
├── scripts/
│   ├── data/           # POD Resource / RefCounted records (D1)
│   ├── systems/        # static-fn-only RefCounted helpers (D9)
│   └── nodes/          # Node-derived gameplay scripts
├── resources/          # *.tres — designer-authored data
│   ├── items/
│   ├── enemies/
│   └── tables/         # condition tables (D7), drop tables, dispatch maps
├── tests/              # GUT tests
└── addons/             # third-party + MCP
```

Three properties earn this layout:

1. **Data and behavior are separated.** `resources/` is `.tres` only — what a
   designer touches. `scripts/` is `.gd` only — what a programmer touches. Both
   touch `scenes/` because that is where the two compose.
2. **The dependency graph has obvious leaves.** `scenes/` and `resources/` never
   import each other in a cycle; the rule is "scripts may reference data, data
   never references scripts." That alignment with the engine's resource graph
   sidesteps the `.tres ↔ .tscn` resource-cycle bug → see Part I, **C17**
   ([#80877](https://github.com/godotengine/godot/issues/80877) tracker;
   [#109771](https://github.com/godotengine/godot/issues/109771)).
3. **`scripts/` is split by *what the script is*, not what it does.** `data/`
   holds POD records; `systems/` holds stateless static-fn helpers; `nodes/`
   holds gameplay Node scripts. That mirrors the three things GDScript files
   actually are at the type level, and aligns with the data-oriented rules
   (Part IV): D1 records live in `data/`, D9 systems live in `systems/`.

The two domain dirs that occasionally trip people up:

- `resources/tables/` is for **dispatch maps and condition tables** that
  designers tune — drop tables, damage multipliers, status-effect curves. This
  is where the D7 table-over-branch rule cashes out as actual files on disk.
- `autoloads/` holds *only* singleton `.gd` files that are registered in
  `[autoload]`. A static-only RefCounted accessed by `class_name` (see below)
  does **not** live here — it goes in `scripts/systems/`.

---

## 5b. Canonical autoloads, and the ones that aren't autoloads

**In plain terms:** most projects need a handful of "always-available"
helpers — a sound hub, a save system, a place to keep collision-layer numbers.
Some of them need to remember things (so they're proper objects that live in
the scene tree); others are just bundles of helper functions and constants (so
they don't need to be loaded as objects at all). Pick the heavier kind only
when you actually need memory or signals.

Every Godot project of nontrivial size grows the same four globals. They split
along one axis: **does this need state?**

- **State (signals, mutable cache, RNG seed, boot-driven init) → autoload `Node`.**
- **No state, just static functions or constants → `class_name`'d RefCounted, no
  autoload entry.**

The autoload pays a per-call indirection cost (3c, measured 4.8.dev:
autoload global identifier ≈ 4.8× inline; a static func on a `class_name`'d
RefCounted ≈ 3.3×).
That's a small constant, but the more important difference is *semantic*: an
autoload exists in the SceneTree and can hold signals; a static-only RefCounted
is purely a namespace for functions and constants. Reach for the autoload when
you actually need what an autoload provides.

| Class | extends | Autoloaded? | Owns |
|---|---|---|---|
| `WorldConstants` | `RefCounted` (static-only) | No — `class_name` global | Collision layer/mask bits, global enums w/ no clear system owner. Cross-system protocol, no state. |
| `SoundBus` | `Node` | Yes | Pub-sub signal hub. Producers emit `SoundBus.sound_played.emit(tag, pos)`; consumers (enemy Ears) subscribe. Decouples producer from consumer set. |
| `SaveSystem` | `Node` | Yes | Save slot read/write, version migration, atomic-write. Owns serialization format. |
| `RegistryRoot` | `Node` | Yes | Boot-references each domain registry (`ItemRegistry`, `EnemyRegistry`, ...) in `_ready` to force their `_static_init` to run early + in known order. Registries self-validate inside `_static_init`. |

`WorldConstants` is the canonical example of the static-only globals tier. It
`extends RefCounted`, lives in `scripts/systems/`, has *no* `[autoload]` entry,
and is accessed by its `class_name` from anywhere in the project. Promotion
goes one direction: static-only RefCounted → autoload Node, the moment state
genuinely shows up (a cache, an RNG seed, a signal to emit). The reverse —
demoting an autoload to static-only — almost never happens, because once a
signal exists, removing it is a refactor across every subscriber.

### Autoload scripts must NOT declare `class_name`

**In plain terms:** if you've already given a script a global nickname by
registering it as an autoload, don't also give it the same nickname via
`class_name` — that's claiming the same name twice, and the engine refuses to
start the script at all.

This is the most common autoload mistake, and the engine error message isn't
obvious until you've seen it once.

**Autoload scripts must NOT declare `class_name`.** The autoload's registered
name (the `[autoload]` key in `project.godot`) is already a global identifier;
a matching `class_name` collides — Godot errors `Class 'Foo' hides an autoload
singleton`. So `SoundBus` / `SaveSystem` / `RegistryRoot` are bare `extends Node`,
accessed by their autoload name (`SaveSystem.write_slot(...)`).

```gdscript
# Bad — save_system.gd is registered as autoload `SaveSystem` in project.godot AND
# declares class_name SaveSystem. Parse Error: Class "SaveSystem" hides an autoload
# singleton — the script won't load, so the autoload never instantiates either.
class_name SaveSystem
extends Node

func write_slot(slot: int, data: Dictionary) -> void:
    _write(slot, data)

# Good — bare `extends Node`, no class_name; reach it by the autoload name. The
# only change is deleting the class_name line.
extends Node

func write_slot(slot: int, data: Dictionary) -> void:
    _write(slot, data)
# call site:  SaveSystem.write_slot(0, save_data)
```

**4.8.dev: confirmed, and it's fatal** (`tests/repro_autoload_classname_proj/`).
A script registered as autoload `Foo` that also declares `class_name Foo` fails to
parse — exact message `Parse Error: Class "Foo" hides an autoload singleton.` —
and because the script then won't load, the autoload itself doesn't instantiate
(`Failed to instantiate an autoload, script ... does not inherit from 'Node'`).
**In plain terms:** the autoload name and a `class_name` are two ways of declaring
the same global name, and you can't declare it twice — naming both `Foo` is like
two `var Foo` at global scope, so the engine rejects the file outright rather than
silently picking one. Pick one spelling: drop the `class_name` (the default), or
give it a different one (`class_name SaveSystemNode` + autoload `SaveSystem`).

Trade-off: the autoload name is **not** usable as a type annotation
(`var s: SaveSystem` fails) — fine for a singleton, since you never hold a
reference *to* the singleton, you call methods on it directly. If you genuinely
need the type too (e.g. you pass the singleton to a helper that wants a typed
param), give the `class_name` a *different* spelling from the autoload key —
`class_name SaveSystemNode` + autoload `SaveSystem`. The canonical default is
no `class_name`.

`class_name` stays only on the **non-autoloaded** exemplars: `WorldConstants`
(static-only RefCounted), the `*Registry` RefCounted tables, and
`Def` / `Record` / `System` classes.

---

## 5c. Naming by kind

**In plain terms:** the language doesn't tell you at a glance whether a file
holds data, holds behavior, or runs the game. So tack on a small suffix
(`Def`, `Record`, `System`, `Manager`, `HUD`) and you can tell each file's job
just by reading its name.

GDScript has no marker that says "this class is a POD record" vs "this class is
a stateless system" — the type system doesn't distinguish. A suffix convention
recovers that distinction and gives every file an immediate, scannable role.

| Kind | Suffix | Lives in | Example |
|---|---|---|---|
| Per-item Resource (saveable/authored) | `Def` | `scripts/data/` + `resources/<domain>/*.tres` | `ItemDef`, `WeaponDef`, `EnemyDef` |
| Transient record (in-memory only) | `Record` / `Result` / `Event` | `scripts/data/` | `HitResult`, `SpawnEvent`, `AIRecord` |
| Static-fn system (stateless behavior) | `System` | `scripts/systems/` | `CombatSystem`, `UpgradeSystem`, `InventorySystem` |
| Registry (per-domain table) | `Registry` | `scripts/systems/` | `ItemRegistry`, `EnemyRegistry` |
| Manager (stateful, owns Array of N) | `Manager` | `autoloads/` or scene root | `EnemyManager`, `SpawnManager` |
| HUD facade (owns widget refs) | `HUD` | `scripts/nodes/` | `HUD`, `CombatHUD` |
| Per-instance gameplay Node | bare | `scripts/nodes/` | `Player`, `Enemy`, `Door` |
| Base scene (inherited by N) | `_base` prefix | `scenes/<domain>/` | `_pickup_base.tscn`, `_enemy_base.tscn` |

Two non-obvious points:

- **`Def` and `Record` both live in `scripts/data/`,** but only `Def` has a
  matching `.tres` under `resources/`. The split is *persistence*: `Def` is the
  designer-authored, saveable kind (`Resource`); `Record` / `Result` / `Event`
  is the in-flight kind that exists for one frame or one transaction
  (`RefCounted`). A `HitResult` doesn't get a `.tres` file because there is no
  authored hit — it's the output of a combat transform.
- **`enum Id` lives inside the system that owns the concept.** `ItemRegistry.Id`,
  `Enemy.AlertState`. There is no global `Enums.gd` god-class. The reason is
  ownership: when you change a label, the change lives next to the code that
  acts on it, not in a file every system has to import. The decision rubric in
  5e covers the `enum` vs `StringName` choice.

---

## 5d. Subsystem shape templates

**In plain terms:** five ready-made layouts for the parts every game ends up
building — a box of loose functions that does the actual work, a master list of
items, a thing that updates lots of enemies at once, a HUD wrapper that holds the
on-screen widgets, and a base scene that other scenes copy from. Copy the shape;
fill in the specifics.

These are not abstract patterns — they are the concrete file shapes that the
rest of this part assumes. Each template carries a label like *(D1 + D11 + C2a)*
naming the data-oriented and engine-bug rules it satisfies.

### System (D6 + D9) — where behavior goes

**In plain terms:** a "system" is a box of loose functions. Nothing gets
constructed; you call them by name — `CarrySystem.can_carry(prop, limit, size)`.
What it replaces is the habit of hanging those same functions on the thing they
act on: a `pick_up()` method on the Player, an `apply()` method on the damage
record. The functions are identical either way. The difference is who owns them,
and ownership is what causes the trouble.

Four plain reasons the box wins:

**1. The same behavior has to serve things that aren't related.** A player and a
training dummy both pick things up, both crouch, both fall off ledges. Neither is
a *kind of* the other — a dummy is not a player with fewer features, and a player
is not a dummy with a camera. If carrying lives on the Player class, the dummy
either inherits from Player (nonsense, and it drags the camera and the input
handling along) or gets a copy of the code that quietly drifts out of sync. As
loose functions, both call the same code and neither one owns it. This is the
reason that actually bites in practice; the others are conveniences by
comparison.

**2. You can run it without running the game.** A function that takes a record
and changes it needs no scene, no window, no node tree — just the record. You can
check it in a headless script that finishes in milliseconds. A method on a Node
needs the Node, which needs the tree, which needs the scene, which needs a
running game. That difference decides whether the behavior gets tested at all.

**3. Everything that can change a thing stays in one file.** Ask "what can alter
a crouch?" and the answer is: read `CrouchSystem`, that's the list. When behavior
rides on the noun instead, every new feature bolts one more method onto Player,
and after a year nobody can enumerate what touches it — the class has become the
place where everything happens, which is the D4 monolith this whole part is
arranged to avoid.

**4. Verbs with two objects have no natural home.** Pushing involves the body
doing the pushing and the loose thing being pushed. Whose method is `push()`?
Both answers are defensible, which is the tell that the question is wrong. As a
system it doesn't arise: `PushSystem.push(body, prop)` names both and belongs to
neither.

It is also the cheapest call the engine offers — 45.4 ns, nothing allocated,
no reference to hold or free (§3c). But speed is a side effect here, not the
argument. The argument is reason 1.

**The honest cost:** you lose `obj.` autocomplete as a way of discovering what
you can do to a thing, and you pass more arguments — `old-keep`'s
`HitReactionSystem.settle()` takes eight. The answer to the second is the first
template's other half: arguments that always travel together become a record
(`HitChannelState`, `CarryState`), and then the system takes two params instead
of nine. If you find yourself passing the same six values everywhere, you've
found a record you haven't written yet.

```gdscript
# Bad — behavior riding on the data. Only a Player can ever do this, and the
# record now needs to know what an Enemy is.
class_name HitResult extends RefCounted
var damage: int
var crit: bool
func apply(target: Enemy) -> void:
    target.health -= damage
    if crit:
        target.stagger()

# Good — the record is dumb, the verb is a static function, and any body at all
# can be the target (D6 + D9).
class_name HitResult extends RefCounted
var damage: int
var crit: bool

class_name CombatSystem extends RefCounted
static func resolve(hit: HitResult, target: Node3D) -> void:
    target.health -= hit.damage
    if hit.crit:
        target.stagger()
```

Shape rules: `class_name`'d RefCounted, every method `static`, no `_init`, never
instantiated, and no `.new()` anywhere. State is the exception and takes exactly
two forms — a frozen registry table (`static var` + `_static_init` +
`make_read_only`, see below) or a per-frame cache keyed by instance id. Anything
else wanting state is a Manager or an autoload, not a System.

**Worked reference.** `old-keep` runs 24 of these: 248 `static func`, zero
instance methods, zero `.new()` call sites, against 30 record classes of which
only four declare a method at all (each an `_init`). `Player` and `Dummy` there
are siblings — both `extends StairsCharacter`, neither derived from the other —
and they share `CarrySystem` (12 call sites vs 15), `LocomotionSystem` (18 vs 9)
and `CrouchSystem` (11 vs 6), while `PerceptionSystem` is 25 call sites in the
dummy and 1 in the player. Under the method-on-the-class shape that split is
either an inheritance lie or a copy.

### Registry (D1 + D11 + C2a)

**In plain terms:** one master list of everything in a category — every
item, every enemy kind. It's read by every system, so it has to be locked
down so nothing can accidentally change it, and it has to be checked at
startup so any missing pieces blow up immediately instead of failing
silently mid-game.

A registry is a per-domain table: every item in the game, every enemy kind,
every weapon. The table is shared mutable data at the worst possible scope
(every system reads it), so the construction has to be locked-down by default.

```gdscript
class_name ItemRegistry extends RefCounted

enum Id { NONE, POTION, SWORD_GRIP, ... }   # enum at API boundary (D10a)

static var ALL: Array[ItemDef] = [
    null,                                 # Id.NONE sentinel
    preload("res://resources/items/potion.tres"),
    preload("res://resources/items/sword_grip.tres"),
    ...
]

static func _static_init() -> void:
    _validate()                           # private — fails loud via push_error/OS.crash
    if not ALL.is_read_only():
        ALL.make_read_only()              # C2a — lock after populate

static func get_def(id: Id) -> ItemDef:
    return ALL[id]                        # direct index, no exists() guard (resource-loading.md)

static func _validate() -> void:
    for id: int in range(1, ALL.size()):  # skip NONE sentinel
        if ALL[id] == null:
            push_error("[ItemRegistry] ALL[%d] is null" % id)
            OS.crash("ItemRegistry validation failed")
```

Three things this shape locks in:

- **`Id.NONE = 0` is a sentinel,** not a real item. The validate loop starts at
  index 1 because index 0 is *deliberately* null — it gives every uninitialized
  `var item_id: Id` a known-bad value to crash on, not a silent default item.
- **`ALL` is `static var`, not `const`.** A `const Array` is shared mutable
  state under a misleading name → **C1** / **C2**
  ([#88753](https://github.com/godotengine/godot/issues/88753),
  [#61274](https://github.com/godotengine/godot/issues/61274)). The
  `make_read_only()` call after populate is the engine-enforced lock — mutations
  raise "Array is in read-only state"; reads still work. That's **C2a**.
- **No parallel `SCENES` array.** Two arrays keyed by the same `enum Id` is a
  mirror registry — coupling, not split (Part IV, **D11**). Derive the pickup
  scene path by convention (Part IV, **D7a**) or fold the path into `ItemDef`
  as a field. The parity-asserting test that would otherwise guard the two
  arrays' length-alignment is the giveaway.

`RegistryRoot` references each registry once (e.g. `var _n: int = ItemRegistry.ALL.size()`)
so each registry validates at boot, fail-loud, with no `validate()` API on the
registry itself. The crash-on-validation-failure path is intentional: a
half-loaded registry that silently returns `null` for a missing item is the
worst possible failure mode, because it surfaces as "potion doesn't heal" at
3am, not "registry boot failed" at startup.

**In plain terms:** there's a special setup function (`_static_init`) that
runs once, automatically, when the engine first reads a class's file off
disk — not when your code later goes to use that class. So if a startup
script even mentions the class by name, that mention is enough to make the
engine load the file and run its setup. Classes nobody mentions stay
unloaded and never run their setup at all.

**Measured (4.8.dev, `tests/repro_static_init_proj/`) — `_static_init` timing is
subtler than "runs the first time the class is referenced":** it runs when the
class's script is first *loaded*, and a script's `class_name` dependencies are
loaded when *that* script loads — not when a reference statement later executes.
The trace nails three things down:

- **It fires at script-load, ahead of `_ready`.** A registry named only inside
  `RegistryRoot._ready`'s *body* still runs its `_static_init` **before**
  `RegistryRoot._ready` executes — because loading the autoload script
  `registry_root.gd` resolves `ItemRegistry` / `EnemyRegistry` as load-time
  dependencies. Both `[static_init]` lines print above `[RR] _ready START`.
- **Reachable, not eager-for-all.** A `class_name`'d registry that *no* loaded
  script references (`UnusedRegistry` in the repro) never runs `_static_init` at
  all. So it's not "every `class_name` class inits at boot" — it's "every
  `class_name` class **reachable from a loaded script** inits."
- **Once, sentinel, lock.** `_static_init` runs exactly once (a later
  re-reference produced no second run), `ALL[0]` (the `NONE` sentinel) is `null`,
  and `make_read_only()` set inside `_static_init` leaves `is_read_only() == true`.

The practical correction: `RegistryRoot`'s job is **reachability**, not "forcing
init from inside `_ready`." By statically naming each registry from a script that
loads at boot, it guarantees they load (and validate) at boot at all. The
*timing* is script-load, before `_ready`; the statement order inside `_ready`
does **not** control static-init order — load-dependency order does (first
lexical reference within the loaded script). If you need a registry to init at
boot, the load-bearing requirement is that *some boot-loaded script names it* —
the `_ready` body is just a convenient, guaranteed-reachable place to do so.

### Manager (batched-tick, D8)

**In plain terms:** instead of every enemy asking the engine "update me"
every frame, one Manager keeps a list of all the live enemies and updates
them in one loop. The win isn't a cheaper call — measured, looping nodes and
calling each one's `tick()` is actually a touch *slower* than letting them
self-update. The win is that dead and distant enemies aren't in the list, so
their work simply doesn't happen.

A manager owns the per-frame loop for N entities of one kind. The per-entity
script does not run `_physics_process` — the manager does, once, over its
cached collection. This is the D8 batched-tick rule made concrete — but heed
D8's measured correction (4g): centralizing the *call* (a `tick()` per
node) is **not** itself a speed-up — it measured ~2× *slower* than per-node
`_physics_process`. The manager earns its keep through the **control** it
enables — skip the dead, LOD the distant — and, for the dispatch win, going
full SoA (manager-owned `Packed*Array`s, no per-entity call).

```gdscript
class_name EnemyManager extends Node

var _alive: Array[Enemy] = []             # cache, refreshed via group signals (D2a)

func _ready() -> void:
    get_tree().node_added_to_group.connect(_on_added)
    get_tree().node_removed_from_group.connect(_on_removed)

func _physics_process(delta: float) -> void:
    for e: Enemy in _alive:               # typed for (H2)
        e.tick(delta)                     # a call per entity — for CONTROL, not a
                                          # dispatch win (4g: ~2× slower than per-node)
```

Per-enemy `set_physics_process(false)` in `_ready` — Manager owns the loop.

The cache is the load-bearing detail. Calling `get_tree().get_nodes_in_group(&"alive")`
inside `_physics_process` would allocate a fresh `Array` every frame
(Part IV, **D2a**). The signal-based refresh keeps the cache live without the
per-frame allocation: enemies enter the alive group on spawn, leave it on
death, and the manager updates `_alive` on the edge.

`class_name EnemyManager` here assumes the Manager is a **scene-root node**
(instanced in a scene, where `class_name` is correct and gives you the type).
If instead you register it in `[autoload]`, **drop the `class_name`** (autoload
name collides with it — see 5b) and access it by the autoload name.

### HUD facade (M11 + M12)

**In plain terms:** instead of every gameplay system reaching directly into
each on-screen widget (health bar, reticle, menu), give it one `HUD` object
that holds them all. Other systems talk to the HUD; the HUD talks to its
widgets. One door instead of ten.

A HUD on a nontrivial game grows five to ten widgets, each one wanting a
reference to the player, the camera rig, the camera. Wiring every controller
directly to every widget produces an N×M reference graph that breaks the moment
you rename a `@onready` path. The facade flattens that to N×1.

```gdscript
class_name HUD extends Control

@onready var _reticle: Reticle = $Reticle
@onready var _scanner_bar: ScannerBar = $ScannerBar
@onready var _interact_menu: InteractMenu = $InteractMenu
@onready var _inventory_overlay: InventoryOverlay = $InventoryOverlay
@onready var _interact_prompt: InteractPrompt = $InteractPrompt

func init_hud(player: Player, rig: PlayerCameraRig, camera: Camera3D) -> void:
    _reticle.init_hud(player, rig, camera)
    _scanner_bar.init_hud(player)
    _interact_menu.init_hud(player)
    ...

func get_interact_menu() -> InteractMenu: return _interact_menu
func is_interact_menu_open() -> bool:
    return _interact_menu != null and _interact_menu.is_open()
```

Parent scene-root calls `_hud.init_hud(...)` once. Controllers borrow widgets
via `_hud.get_*()` getters (null-safe wrappers like `is_interact_menu_open()`
for gating sites). 5 `@onready` → 1 `_hud` ref on parent.

**`@onready var _x = $Path` vs `@export var _x: T` for the widgets themselves.**
The example wires each widget with `@onready var _reticle: Reticle = $Reticle` —
a hardcoded node path. That's the right default *once the HUD's own subtree has
settled*: the path is short, local to the scene, and reads as intent. But the
path is a string baked into the script, and the engine doesn't know it refers to
a node — rename `$Reticle` to `$ReticleRoot` in the scene, or reparent it one
level, and `@onready var _reticle = $Reticle` silently resolves to `null` and
fails at first access, not at edit time. While the HUD layout is still in flux —
widgets getting added, regrouped under containers, renamed — prefer
`@export var _reticle: Reticle` and wire each ref in the inspector. An exported
node reference is a real link the editor *tracks*: move or rename the node and
Godot rewrites the reference for you, so a tree restructure doesn't break the
HUD. The cost is that the wiring lives in the `.tscn`, not the script, so it's
less visible in a diff. The rule of thumb: `@export` node refs while the layout
is undecided and paths churn; collapse to `@onready $Path` once the subtree is
stable and you want the wiring legible in the script. (This is the *own-child*
case — distinct from M11, which is about *sibling/cross-system* refs, where typed
`init_*()` push-injection beats both.)

This is **M11** (push-injection over `@export NodePath`) and **M12**
(deferred-boot-check) cashing out together: typed `init_hud(...)` gives you
compile-time errors on misconfig, and the facade pattern means a controller
that needs three widgets doesn't import three widget classes — it imports
`HUD` and calls three getters.

### Pickup scene — scene inheritance

**In plain terms:** when ten item-pickup scenes are nearly identical,
make one "base" scene with the shared parts and have the others inherit
from it. Each variant only sets the few things that differ (the model,
the data file). Edit the base once; all variants update.

When N scenes share a root setup (script + collision layer/mask + skeleton
children), extract a base `.tscn` and use `instance=ExtResource(base)` in the
derived scenes. The derived scenes override only the per-instance delta.

`scenes/items/_pickup_base.tscn` root: `StaticBody3D` + `item_pickup.gd` script
+ collision_layer=`LAYER_INTERACTABLE` (so the player's interact raycast hits
it) / mask=0 (pickup doesn't actively scan) + placeholder MeshInstance3D +
CollisionShape3D children. Derived (`sword.tscn`, `potion.tscn`)
`instance=ExtResource(_pickup_base)` and override only `item` (Def ref),
`mesh`, `shape`.

One constraint that catches everyone once: derived scenes reference children
**by the base's exact node names** (Godot diff-merges by name + index). Don't
rename base children later without sweeping derived scenes. The `_base`
filename prefix exists partly to flag this — it's a scene that other scenes
depend on by name.

---

## 5e. The decision rubric

**In plain terms:** a one-line cheat sheet for the small choices that come up
again and again. Pick the default in the table unless you have a specific
reason not to; each row points back at the rule that explains why.

The shapes above answer the common questions structurally. The table below
answers them one at a time — what to default to when the question first comes
up on a new subsystem.

| Question | Default | Rule |
|---|---|---|
| Data class: `Resource` or `RefCounted`? | `Resource` if saveable/editor-authored; `RefCounted` if transient | [`dod.md`](../rules/dod.md) D1 |
| Label set: `enum` or `StringName`? | `enum` for closed/finite sets; `StringName` only for engine APIs or string-like ops | [`dod.md`](../rules/dod.md) D10/D10a |
| Optional state: bool flag or set membership? | Group/dict membership over `_dead: bool` / `_alerted: bool` | [`dod.md`](../rules/dod.md) D2 |
| Set ID: `is Player` or `is_in_group(&"player")`? | `is Player` when class-narrowing fits — same O(1), compile-time-checked | [`dod.md`](../rules/dod.md) D2a |
| Membership container: group or owner-held array? | group only if tree-wide + decoupled consumers + no single owner; else the owner's typed `Array[T]` / `Dictionary[int, T]` | [`dod.md`](../rules/dod.md) D2b |
| Helper: static-RefCounted or autoload Node? | static-RefCounted; promote only when state needed | [`dod.md`](../rules/dod.md) D9 |
| `class_name` on an autoload script? | No — collides with the autoload name (`Class hides an autoload singleton`). Bare `extends Node`, access by autoload name | 5b above |
| Cross-system / serialized ref: object or ID? | Integer ID + resolve at use site; object refs only for parent→child + sibling-by-injection | [`dod.md`](../rules/dod.md) D3 |
| Sibling ref inside scene: `@export NodePath` or typed `init_*()`? | Typed `init_*()` push-injection from scene-root script | [`style.md`](../rules/style.md) M11 |
| Dispatch chain >5 arms: `if/elif` or `Dictionary` lookup? | Dict keyed by discriminator; designer-tunable → move to `.tres` | [`dod.md`](../rules/dod.md) D7 |
| `enum` → file path: `Id.keys()[i].to_lower()` or explicit helper? | `if/elif` helper — no alloc, per-slot override, loud default (not `match`, D7b) | [`dod.md`](../rules/dod.md) D7a |
| Monolithic class w/ fields touched by N systems | Decompose into per-concern containers (Dict by ID, group, manager-owned array) | [`dod.md`](../rules/dod.md) D4 |
| Per-kind constants on every instance? | Move cold to shared `EnemyDef` Resource referenced by N instances | [`dod.md`](../rules/dod.md) D5 |
| Method mutates a passed-in target? | Extract to `static func` on system class | [`dod.md`](../rules/dod.md) D6 |
| Two arrays sharing same `enum Id` index? | One is a mirror — fold into D1 record or derive by convention | [`dod.md`](../rules/dod.md) D11 |
| `preload` or `load`? | Preload constants (defs, icons, tables); load variables (pickup scenes, story content) | [`resource-loading.md`](../rules/resource-loading.md) |
| Boot validator expensive (instantiate scenes)? | Wrap in `if OS.has_feature("editor"):` | [`style.md`](../rules/style.md) M10a |
| Inverse `.tres → .tscn` ref? | Convention-derived (D7a) or String path. Never `PackedScene` ext_resource on `.tres` | [`engine-bugs.md`](../rules/engine-bugs.md) C17 |
| Flagged `has_method(&"...")` + `call(&"...")` | Extract shared base class, dispatch via `is` | [`style.md`](../rules/style.md) H13 |

When project-local rules conflict, project wins. The rubric is a default for
the "I haven't decided yet" case, not an override of a project that has
genuine reasons to deviate.

---

## 5f. Boot order

**In plain terms:** the always-available helpers load in the order listed in
the project file, and that order matters when one of them depends on another.
Load the master lists first, then save/load (which uses them), then the
sound hub. If anything is wrong, crash the game right there at startup
instead of limping along.

`autoloads/` load in `project.godot` order. Order matters when one autoload
references another:

```ini
# project.godot
[autoload]
RegistryRoot="*res://autoloads/registry_root.gd"
SaveSystem="*res://autoloads/save_system.gd"
SoundBus="*res://autoloads/sound_bus.gd"
```

1. **`RegistryRoot`** — forces every per-domain registry's `_static_init` by
   referencing it in `_ready`. Registries self-validate in `_static_init` and
   crash loud on failure.
2. **`SaveSystem`** — depends on registries (deserialize by ID).
3. **`SoundBus`** — pure pub-sub, no deps.

`RegistryRoot` itself is tiny — it exists only to *name* each registry, so the
engine loads (and thereby validates) it at boot:

```gdscript
# autoloads/registry_root.gd — autoload #1, bare `extends Node` (no class_name, 5b).
extends Node

func _ready() -> void:
    # Each reference forces that registry's script to load → _static_init → _validate.
    var _items: int = ItemRegistry.ALL.size()
    var _enemies: int = EnemyRegistry.ALL.size()
```

`WorldConstants` is **not** autoloaded — it's a `class_name`'d static-only
RefCounted, accessed globally without an `[autoload]` entry. See **D9** in
Part IV.

The fail-loud discipline is what makes this order safe to rely on: if
`ItemRegistry` can't validate (a `.tres` is missing, a `Def` has a wrong
field), `_static_init` calls `OS.crash` before `SaveSystem` ever runs. There
is no path where a half-loaded registry quietly returns `null` from `get_def`
and the bug surfaces three hours into a playtest. The `_static_init` path
makes this automatic: the moment `RegistryRoot._ready` touches a broken
registry, the crash fires before any gameplay code runs.

`push_error` alone is not enough — Godot prints to stderr and keeps going,
which is exactly what you don't want at boot. `OS.crash` after `push_error` is
the pair: the error gives you the diagnostic, the crash stops the bleed.

One measured caveat on *when* this fires (full repro in 5d): a registry's
`_static_init` validation runs at the **load** of the first boot-loaded script
that names it, which is **before** `RegistryRoot._ready` executes — not at the
`_ready` reference statement. So the crash, if a `.tres` is missing, can fire
during autoload script loading, ahead of `RegistryRoot._ready` ever running.
The order registries validate in follows load-dependency order, not the order
of statements in `_ready`. What `RegistryRoot` guarantees is **reachability** —
that each registry is named by a boot-loaded script at all — which is the real
precondition for boot-time validation. The observed order
(`tests/repro_static_init_proj/`):

```
[ItemRegistry] _static_init     # at script-load…
[EnemyRegistry] _static_init    #   …both fire BEFORE _ready's first line
[RR] _ready START
```

---

## 5g. When to break the skeleton

**In plain terms:** the layout above is the starting default, not a law. A
tiny tool, a game jam entry, or a genuinely unusual project gets to ignore
it. Wait until the same exception shows up on two or three projects before
you decide it's a new rule.

The skeleton is the *default*, not the prescription. Break it when:

- **One-shot tool or level editor.** A jam game or a procgen testbed doesn't
  earn `autoloads/` + `scripts/{data,systems,nodes}/` + `resources/`. Flatter
  directory, fewer suffixes, less rigor — the layout exists to keep a
  ten-system project legible, not a fifty-line script.
- **Genuinely novel domain.** No existing rule fits, and the rubric in 5e
  doesn't have a row for the question you're asking. Carry the local
  convention in a project-level `CLAUDE.md` or `rules/` override. If the same
  delta shows up on a second project, promote it back here.
- **Three projects ship the same delta from this skeleton.** That's the
  signal: it's time to update *this file*, not re-derive the same exception on
  every new project.

The one-shot-tool case is the most common break — it collapses the whole
skeleton to a flat handful of files:

```
# game-jam entry — no autoloads/, no scripts/{data,systems,nodes} split
project_root/
├── project.godot
├── main.gd          # input + spawn + score, all in one file
├── player.gd
├── enemy.gd
└── assets/
```

The base anti-overengineering rule applies: three similar lines beats a
premature abstraction. Don't add containers, autoloads, or managers
speculatively — wait for the second instance. A `Manager` for one enemy kind
is overhead; a `Manager` for six enemy kinds is structure. The line between
the two only becomes obvious in retrospect, which is why the rule is "wait for
the second instance," not "predict where the abstraction will land."

---

## The shape, in one paragraph

**In plain terms:** the whole chapter, boiled down — where files go, what
to name them, which globals are full objects vs. just bundles of functions,
and which one-paragraph rule covers each common decision.

Data is `.tres` under `resources/` and a `Def` `Resource` class under
`scripts/data/`. Behavior is a `static func` on a `System` `RefCounted` under
`scripts/systems/`, or, when it needs state, a `Manager` `Node` in
`autoloads/` or on a scene root. Cross-system globals split on whether they
need state: `class_name`'d static-only RefCounted if not (no `[autoload]`
entry), `Node` autoload if they do (and then no `class_name`, or the engine
errors). Registries are static tables locked with `make_read_only()` after
validate, validated at boot via `_static_init` referenced from `RegistryRoot`,
fail loud with `OS.crash`. Per-frame loops live on a manager, not on N
entities. Sibling refs inside a scene are typed `init_*()` push-injection, not
`@export NodePath`. Cross-system refs are integer IDs, resolved at the use
site. Mirror registries — two arrays keyed by the same enum — are coupling,
not a split. When in doubt, the decision rubric in 5e has the default.
