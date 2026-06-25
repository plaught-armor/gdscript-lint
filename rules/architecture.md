# GDScript — Architecture

Cross-project skeleton + decision rubric. Scaffolds for new Godot projects + answers "where does X live?"

## Dir layout

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

Why: data (`resources/`) separate from behavior (`scripts/`); leaves of dep graph (`scenes/`, `resources/`) never import scripts/ → no `.tres ↔ .tscn` cycles (C17). Designer touches `resources/`, programmer touches `scripts/`, both touch `scenes/`.

## Canonical autoloads + globals

Every Godot project ships these. **Autoloads** require state (signals, mutable cache) or `_ready`-driven boot logic. **Static-only RefCounted globals** (no autoload entry) are accessed by `class_name` and pay no autoload cost.

| Class | extends | Autoloaded? | Owns |
|---|---|---|---|
| `WorldConstants` | `RefCounted` (static-only) | No — `class_name` global | Collision layer/mask bits, global enums w/ no clear system owner. Cross-system protocol, no state. |
| `SoundBus` | `Node` | Yes | Pub-sub signal hub. Producers emit `SoundBus.sound_played.emit(tag, pos)`; consumers (enemy Ears) subscribe. Decouples producer from consumer set. |
| `SaveSystem` | `Node` | Yes | Save slot read/write, version migration, atomic-write. Owns serialization format. |
| `RegistryRoot` | `Node` | Yes | Boot-references each domain registry (`ItemRegistry`, `EnemyRegistry`, ...) in `_ready` to force their `_static_init` to run early + in known order. Registries self-validate inside `_static_init`. |

Promotion path: static-only RefCounted → autoload Node only when state genuinely needed (cache, RNG seed, signals). See [`dod.md`](dod.md) D9. WorldConstants is the canonical static-only exemplar — `extends RefCounted`, lives in `scripts/systems/`, no `[autoload]` entry.

**Autoload scripts must NOT declare `class_name`.** The autoload's registered name (the `[autoload]` key in `project.godot`) is already a global identifier; a matching `class_name` collides — Godot errors `Class 'Foo' hides an autoload singleton`. So `SoundBus`/`SaveSystem`/`RegistryRoot` are bare `extends Node`, accessed by their autoload name (`SaveSystem.write_slot(...)`). Trade-off: the autoload name is **not** usable as a type annotation (`var s: SaveSystem` fails) — fine for a singleton. If you genuinely need the type too, give the `class_name` a *different* spelling from the autoload key (e.g. `class_name SaveSystemNode` + autoload `SaveSystem`); the canonical default is no `class_name`. `class_name` stays only on the **non-autoloaded** exemplars: `WorldConstants` (static-only RefCounted), the `*Registry` RefCounted tables, and `Def`/`Record`/`System` classes.

## Naming by kind

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

`enum Id` lives inside the system that owns the concept (`ItemRegistry.Id`, `Enemy.AlertState`). No global `Enums.gd` god-class — see decision rubric below.

## Subsystem shape templates

### Registry (D1 + D11 + C2a)

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

No parallel `SCENES` array — derive pickup-scene path by convention (D7a) or fold into `ItemDef` field. See [`dod.md`](dod.md) D11.

`_static_init` runs the first time the class is referenced. `RegistryRoot._ready` references each registry once (e.g. `var _n: int = ItemRegistry.ALL.size()`) to force the static-init order at boot — predictable, fail-loud, no `validate()` API on the registry itself.

### Manager (batched-tick, D8)

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

`class_name EnemyManager` here assumes the Manager is a **scene-root node** (instanced in a scene, where `class_name` is correct and gives you the type). If instead you register it in `[autoload]`, **drop the `class_name`** (autoload name collides with it — see the autoloads note above) and access it by the autoload name.

### HUD facade (M11 + M12)

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

Parent scene-root calls `_hud.init_hud(...)` once. Controllers borrow widgets via `_hud.get_*()` getters (null-safe wrappers like `is_interact_menu_open()` for gating sites). 5 `@onready` → 1 `_hud` ref on parent.

### Pickup scene (style.md "Scene inheritance")

`scenes/items/_pickup_base.tscn` root: `StaticBody3D` + `item_pickup.gd` script + collision_layer=`LAYER_INTERACTABLE` (so the player's interact raycast hits it) / mask=0 (pickup doesn't actively scan) + placeholder MeshInstance3D + CollisionShape3D children. Derived (`sword.tscn`, `potion.tscn`) `instance=ExtResource(_pickup_base)` and override only `item` (Def ref), `mesh`, `shape`.

## Decision rubric

| Question | Default | Rule |
|---|---|---|
| Data class: `Resource` or `RefCounted`? | `Resource` if saveable/editor-authored; `RefCounted` if transient | [`dod.md`](dod.md) D1 |
| Label set: `enum` or `StringName`? | `enum` for closed/finite sets; `StringName` only for engine APIs or string-like ops | [`dod.md`](dod.md) D10/D10a |
| Optional state: bool flag or set membership? | Group/dict membership over `_dead: bool` / `_alerted: bool` | [`dod.md`](dod.md) D2 |
| Set ID: `is Player` or `is_in_group(&"player")`? | `is Player` when class-narrowing fits — same O(1), compile-time-checked | [`dod.md`](dod.md) D2a |
| Membership container: group or owner-held array? | group only if tree-wide + decoupled consumers + no single owner; else the owner's typed `Array[T]` / `Dictionary[int, T]` | [`dod.md`](dod.md) D2b |
| Helper: static-RefCounted or autoload Node? | static-RefCounted; promote only when state needed | [`dod.md`](dod.md) D9 |
| `class_name` on an autoload script? | No — collides with the autoload name (`Class hides an autoload singleton`). Bare `extends Node`, access by autoload name | "Canonical autoloads" note above |
| Cross-system / serialized ref: object or ID? | Integer ID + resolve at use site; object refs only for parent→child + sibling-by-injection | [`dod.md`](dod.md) D3 |
| Sibling ref inside scene: `@export NodePath` or typed `init_*()`? | Typed `init_*()` push-injection from scene-root script | [`style.md`](style.md) M11 |
| Dispatch chain >5 arms: `if/elif` or `Dictionary` lookup? | Dict keyed by discriminator; designer-tunable → move to `.tres` | [`dod.md`](dod.md) D7 |
| `enum` → file path: `Id.keys()[i].to_lower()` or explicit helper? | `if/elif` helper — no alloc, per-slot override, loud default (not `match`, D7b) | [`dod.md`](dod.md) D7a |
| Monolithic class w/ fields touched by N systems | Decompose into per-concern containers (Dict by ID, group, manager-owned array) | [`dod.md`](dod.md) D4 |
| Per-kind constants on every instance? | Move cold to shared `EnemyDef` Resource referenced by N instances | [`dod.md`](dod.md) D5 |
| Method mutates a passed-in target? | Extract to `static func` on system class | [`dod.md`](dod.md) D6 |
| Two arrays sharing same `enum Id` index? | One is a mirror — fold into D1 record or derive by convention | [`dod.md`](dod.md) D11 |
| `preload` or `load`? | Preload constants (defs, icons, tables); load variables (pickup scenes, story content) | [`resource-loading.md`](resource-loading.md) |
| Boot validator expensive (instantiate scenes)? | Wrap in `if OS.has_feature("editor"):` | [`style.md`](style.md) M10a |
| Inverse `.tres → .tscn` ref? | Convention-derived (D7a) or String path. Never `PackedScene` ext_resource on `.tres` | [`engine-bugs.md`](engine-bugs.md) C17 |
| Flagged `has_method(&"...")` + `call(&"...")` | Extract shared base class, dispatch via `is` | [`style.md`](style.md) H13 |

When project-local rules conflict, project wins.

## Boot order

`autoloads/` load in `project.godot` order. Order matters when one autoload references another:

1. `RegistryRoot` — forces every per-domain registry's `_static_init` by referencing it in `_ready`. Registries self-validate in `_static_init` and crash loud on failure.
2. `SaveSystem` — depends on registries (deserialize by ID).
3. `SoundBus` — pure pub-sub, no deps.

`WorldConstants` is **not** autoloaded — it's a `class_name`'d static-only RefCounted, accessed globally without an `[autoload]` entry. See D9.

Boot-fail loud: `push_error` + `OS.crash` if a registry can't validate — never let a half-loaded registry hide behind null returns. The `_static_init` path makes this automatic: the moment `RegistryRoot._ready` touches a broken registry, the crash fires before any gameplay code runs.

## When to break the skeleton

The skeleton is the *default*, not the prescription. Break when:

- One-shot tool / level editor → flatter dir, less rigor.
- Genuinely novel domain — no existing rule fits → carry as project-local convention, promote back here if it generalizes.
- Three projects ship the same delta → time to update this file, not re-derive each time.

Three similar lines beats premature abstraction (base anti-overengineering rule). Don't add containers / autoloads / managers speculatively — wait for the second instance.
