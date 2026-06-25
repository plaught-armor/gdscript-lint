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

---

## 1. Directory layout

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
   sidesteps the `.tres ↔ .tscn` cycle bug → see Part I, **C17**
   ([#98551](https://github.com/godotengine/godot/issues/98551)).
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

## 2. Canonical autoloads, and the ones that aren't autoloads

Every Godot project of nontrivial size grows the same four globals. They split
along one axis: **does this need state?**

- **State (signals, mutable cache, RNG seed, boot-driven init) → autoload `Node`.**
- **No state, just static functions or constants → `class_name`'d RefCounted, no
  autoload entry.**

The autoload pays a per-call indirection cost (Part III §2: autoload global
identifier ≈ 2.43× inline; a static func on a `class_name`'d RefCounted ≈ 2.27×).
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

### 2a. Autoload scripts must NOT declare `class_name`

This is the most common autoload mistake, and the engine error message isn't
obvious until you've seen it once.

**Autoload scripts must NOT declare `class_name`.** The autoload's registered
name (the `[autoload]` key in `project.godot`) is already a global identifier;
a matching `class_name` collides — Godot errors `Class 'Foo' hides an autoload
singleton`. So `SoundBus` / `SaveSystem` / `RegistryRoot` are bare `extends Node`,
accessed by their autoload name (`SaveSystem.write_slot(...)`).

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

## 3. Naming by kind

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
  §6 covers the `enum` vs `StringName` choice.

---

## 4. Subsystem shape templates

These are not abstract patterns — they are the concrete file shapes that the
rest of this part assumes. Each template carries a label like *(D1 + D11 + C2a)*
naming the data-oriented and engine-bug rules it satisfies.

### 4a. Registry (D1 + D11 + C2a)

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

`_static_init` runs the first time the class is referenced. `RegistryRoot._ready`
references each registry once (e.g. `var _ := ItemRegistry.ALL.size()`) to force
the static-init order at boot — predictable, fail-loud, no `validate()` API on
the registry itself. The crash-on-validation-failure path is intentional: a
half-loaded registry that silently returns `null` for a missing item is the
worst possible failure mode, because it surfaces as "potion doesn't heal" at
3am, not "registry boot failed" at startup.

### 4b. Manager (batched-tick, D8)

A manager owns the per-frame loop for N entities of one kind. The per-entity
script does not run `_physics_process` — the manager does, once, over its
cached collection. This is the D8 batched-tick rule made concrete.

```gdscript
class_name EnemyManager extends Node

var _alive: Array[Enemy] = []             # cache, refreshed via group signals (D2a)

func _ready() -> void:
    get_tree().node_added_to_group.connect(_on_added)
    get_tree().node_removed_from_group.connect(_on_removed)

func _physics_process(delta: float) -> void:
    for e: Enemy in _alive:               # typed for (H2)
        e.tick(delta)
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
name collides with it — see §2a) and access it by the autoload name.

### 4c. HUD facade (M11 + M12)

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

This is **M11** (push-injection over `@export NodePath`) and **M12**
(deferred-boot-check) cashing out together: typed `init_hud(...)` gives you
compile-time errors on misconfig, and the facade pattern means a controller
that needs three widgets doesn't import three widget classes — it imports
`HUD` and calls three getters.

### 4d. Pickup scene — scene inheritance

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

## 5. The decision rubric

The shapes above answer the common questions structurally. The table below
answers them one at a time — what to default to when the question first comes
up on a new subsystem.

| Question | Default | Rule |
|---|---|---|
| Data class: `Resource` or `RefCounted`? | `Resource` if saveable/editor-authored; `RefCounted` if transient | [`dod.md`](../rules/dod.md) D1 |
| Label set: `enum` or `StringName`? | `enum` for closed/finite sets; `StringName` only for engine APIs or string-like ops | [`dod.md`](../rules/dod.md) D10/D10a |
| Optional state: bool flag or set membership? | Group/dict membership over `_dead: bool` / `_alerted: bool` | [`dod.md`](../rules/dod.md) D2 |
| Set ID: `is Player` or `is_in_group(&"player")`? | `is Player` when class-narrowing fits — same O(1), compile-time-checked | [`dod.md`](../rules/dod.md) D2a |
| Helper: static-RefCounted or autoload Node? | static-RefCounted; promote only when state needed | [`dod.md`](../rules/dod.md) D9 |
| `class_name` on an autoload script? | No — collides with the autoload name (`Class hides an autoload singleton`). Bare `extends Node`, access by autoload name | §2a above |
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

## 6. Boot order

`autoloads/` load in `project.godot` order. Order matters when one autoload
references another:

1. **`RegistryRoot`** — forces every per-domain registry's `_static_init` by
   referencing it in `_ready`. Registries self-validate in `_static_init` and
   crash loud on failure.
2. **`SaveSystem`** — depends on registries (deserialize by ID).
3. **`SoundBus`** — pure pub-sub, no deps.

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

---

## 7. When to break the skeleton

The skeleton is the *default*, not the prescription. Break it when:

- **One-shot tool or level editor.** A jam game or a procgen testbed doesn't
  earn `autoloads/` + `scripts/{data,systems,nodes}/` + `resources/`. Flatter
  directory, fewer suffixes, less rigor — the layout exists to keep a
  ten-system project legible, not a fifty-line script.
- **Genuinely novel domain.** No existing rule fits, and the rubric in §5
  doesn't have a row for the question you're asking. Carry the local
  convention in a project-level `CLAUDE.md` or `rules/` override. If the same
  delta shows up on a second project, promote it back here.
- **Three projects ship the same delta from this skeleton.** That's the
  signal: it's time to update *this file*, not re-derive the same exception on
  every new project.

The base anti-overengineering rule applies: three similar lines beats a
premature abstraction. Don't add containers, autoloads, or managers
speculatively — wait for the second instance. A `Manager` for one enemy kind
is overhead; a `Manager` for six enemy kinds is structure. The line between
the two only becomes obvious in retrospect, which is why the rule is "wait for
the second instance," not "predict where the abstraction will land."

---

## The shape, in one paragraph

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
not a split. When in doubt, the decision rubric in §5 has the default.
