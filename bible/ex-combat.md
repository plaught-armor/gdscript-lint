# DOD by example: an enemy-combat system, end to end

Part IV gives the rules one at a time, each with a small bad/good snippet. This
walks a *single subsystem* — enemy combat — from the naive object-oriented shape
to a data-oriented one, so you can see the rules **compose** rather than stand
alone. The code is real and runnable: [`tests/example_dod_combat_proj/`](../tests/example_dod_combat_proj/),
verified on Godot 4.8.dev (output at the bottom is a literal run, not a sketch).

**In plain terms:** instead of ten separate "do it this way" tips, here's one
small game system built the data-oriented way from start to finish — the files,
how they fit together, and proof it actually runs.

---

## The naive shape (what the instinct produces)

The reflex is one class that *is* an enemy — data and behavior together, one
object per monster:

```gdscript
# The strawman. Every enemy is a fat Node carrying all its own state + behavior.
class_name Enemy extends Node3D
var max_health: int = 10        # cold: never changes for this kind
var health: int = 10            # hot: changes every hit
var speed: float = 1.0          # cold
var contact_damage: int = 2     # cold
var armor: int = 0              # cold
var _dead: bool = false         # a flag to keep in sync
var _attacker: Node = null      # a live ref that can dangle

func _physics_process(delta):   # N of these ticking themselves
    if _dead: return
    position.x = maxf(0.0, position.x - speed * delta)

func take_damage(amount, crit, attacker):
    if _dead: return
    _attacker = attacker        # holds a Node that may free before we use it
    var mult = 1.0
    if armor == 0: mult = 1.0   # branch chain that grows per armor kind
    elif armor == 1: mult = 0.7
    elif armor == 2: mult = 0.4
    health -= int(round(amount * mult * (2 if crit else 1)))
    if health <= 0: _die()

func _die():
    _dead = true                # flag now disagrees with "still in the tree"
    # ... and we still _physics_process every frame, just to early-return
```

Five smells, one per rule it's about to break:

- **Cold and hot data co-mingled** (`max_health`/`speed`/`armor` next to
  `health`/`position`) — repeated on every instance (**D5**).
- **A `_dead` flag** that has to be kept in sync with reality (**D2**).
- **A live `_attacker` Node ref** that dangles if the attacker frees first
  (**D3**, Part I **C8**).
- **An armor `if/elif` chain** that grows every time a designer adds armor
  (**D7**).
- **N self-ticking `_physics_process` callbacks**, each paying per-node dispatch
  (**D8**).

And behavior (`take_damage`) lives *on the data*, so you can't test the damage
math without instancing a `Node3D` in a SceneTree (**D6**).

---

## The data-oriented shape

Six small files, each with one job. The file map:

| File | Role | Rules |
|---|---|---|
| `enemy_def.gd` | `EnemyDef` Resource — the **cold** per-kind constants | D1, D5 |
| `enemy_registry.gd` | `EnemyRegistry` — shared def table, locked read-only | D1, D5, C2a |
| `hit_record.gd` | `HitRecord` — transient hit, attacker by **id** | D1, D3 |
| `combat_system.gd` | `CombatSystem.resolve()` — pure transform + armor **table** | D6, D7 |
| `enemy_manager.gd` | `EnemyManager` — **hot** state in parallel arrays, batched tick, swap-back death | D2, D3, D4, D5, D8, P6 |
| `main.gd` | the driver — spawns, ticks, attacks, prints | — |

### Cold data, defined once (D1, D5)

`EnemyDef` is plain data — the constants that are the same for every grunt:

```gdscript
class_name EnemyDef extends Resource
@export var kind_name: StringName = &""
@export var max_health: int = 10
@export var speed: float = 1.0
@export var contact_damage: int = 1
@export var armor: Armor = Armor.NONE
```

`EnemyRegistry` holds one row per kind, shared by every runtime instance, and
locks it read-only after build (**C2a**) so nothing mutates the shared table:

```gdscript
static var defs: Array[EnemyDef] = [
	EnemyDef.new(&"grunt", 10, 1.0, 2, EnemyDef.Armor.NONE),
	EnemyDef.new(&"brute", 40, 0.5, 6, EnemyDef.Armor.HEAVY),
	EnemyDef.new(&"skirmisher", 6, 2.0, 1, EnemyDef.Armor.LIGHT),
]
static func _static_init() -> void:
	if not defs.is_read_only():
		defs.make_read_only()
```

A thousand grunts share *one* `EnemyDef`; no instance carries its own copy of
`max_health` or `armor`.

### Hot data, split by access pattern (D4, D5)

The manager owns the per-frame state as **parallel arrays indexed by slot** —
not a fat object per enemy. Each system touches only the array it needs:

```gdscript
var _id: PackedInt64Array = []       # stable entity id per slot (D3)
var _kind: PackedInt32Array = []     # which EnemyDef — a cold *reference* (D5)
var _health: PackedInt32Array = []   # hot
var _pos_x: PackedFloat32Array = []  # hot
var _slot_of: Dictionary[int, int] = {}   # id -> slot (D3 resolve)
```

`_kind` is the hot/cold bridge: a slot stores a tiny integer index, and
`def_at(slot)` resolves it to the shared `EnemyDef` only when cold data is
needed.

### Existence-based life, swap-back death (D2, P6)

There is no `_dead` bool. A slot's **presence in the arrays is "alive"**; death
is removal. And removal is **swap-back** — O(1), not an O(n) shift (the P6 rule
from this very corpus):

```gdscript
func kill(slot: int) -> void:
	var dead_id: int = _id[slot]
	var last: int = _id.size() - 1
	if slot != last:
		var moved_id: int = _id[last]
		_id[slot] = _id[last]; _kind[slot] = _kind[last]
		_health[slot] = _health[last]; _pos_x[slot] = _pos_x[last]
		_slot_of[moved_id] = slot      # the moved entity's id now points here
	_id.resize(last); _kind.resize(last)
	_health.resize(last); _pos_x.resize(last)
	_slot_of.erase(dead_id)
```

The `_slot_of` fix-up is the load-bearing detail: swap-back reshuffles slots, so
the id→slot map is updated for the entity that moved. That's what keeps **D3**
working across a kill.

`kill(slot)` is the right tool for **one** removal. For a **mass** removal — an
AoE drops a dozen at once — repeated swap-back loses to a single **write-cursor
compaction** ([removing dead entities](note-removing-dead-entities.md), measured). The
manager carries both; `cull()` packs survivors down in one pass and keeps order:

```gdscript
func cull() -> int:                       # remove every slot with health <= 0
	var n: int = _id.size()
	var w: int = 0                        # write cursor
	for r: int in n:                      # read cursor — each slot touched once
		if _health[r] > 0:
			if w != r:
				_id[w] = _id[r]; _kind[w] = _kind[r]
				_health[w] = _health[r]; _pos_x[w] = _pos_x[r]
			_slot_of[_id[w]] = w; w += 1
		else:
			_slot_of.erase(_id[r])
	_id.resize(w); _kind.resize(w); _health.resize(w); _pos_x.resize(w)
	return n - w                          # how many were removed
```

### Behavior as a pure transform, dispatch as a table (D6, D7)

`CombatSystem` never instantiates. `resolve()` is a static function that takes
data and returns a verdict; the armor multiplier is a **table**, not a branch
chain:

```gdscript
# static var + make_read_only, NOT const — const collections are the shared-
# mutable-ref bug (C1/C2); this mirrors EnemyRegistry.defs (C2a).
static var armor_mult: Dictionary[int, float] = {
	EnemyDef.Armor.NONE: 1.0, EnemyDef.Armor.LIGHT: 0.7, EnemyDef.Armor.HEAVY: 0.4,
}
static func _static_init() -> void:
	if not armor_mult.is_read_only():
		armor_mult.make_read_only()

static func resolve(mgr: EnemyManager, slot: int, hit: HitRecord) -> bool:
	var mult: float = armor_mult[mgr.def_at(slot).armor]
	var dealt: int = int(roundf(hit.amount * mult * (2.0 if hit.crit else 1.0)))
	mgr.apply_damage(slot, dealt)
	return mgr.health_at(slot) <= 0
```

A new armor class is a new *row* in `armor_mult`; `resolve()` never changes. And
the damage math is testable with no SceneTree — feed it a manager and a
`HitRecord`, read the result.

### One batched tick (D8)

The manager owns the loop; enemies don't self-process:

```gdscript
func tick(dt: float) -> void:
	for slot: int in _id.size():
		var def: EnemyDef = EnemyRegistry.get_def(_kind[slot])
		_pos_x[slot] = maxf(0.0, _pos_x[slot] - def.speed * dt)
```

---

## The frame, traced

What `main.gd` runs (six enemies, two removal phases):

1. **Spawn** six enemies → appends to each parallel array; `_slot_of` maps id →
   slot. No `Node3D`, no scene instance.
2. **Tick ×3** → one `for` loop per tick advances every `_pos_x` toward 0.
3. **Phase 1 — single removals.** Snipe the two skirmishers; each lethal hit is a
   `kill(slot)` **swap-back** (O(1), one removal). The last slot fills the hole and
   its id→slot entry updates.
4. **Phase 2 — mass removal.** A flat AoE blasts the survivors; the two grunts
   drop, the brutes (40 hp) live. One `cull()` **write-cursor compaction** packs
   the survivors down in a single pass — *not* two more swap-backs — and keeps
   their relative order.
5. **Resolve ids again** → survivors still resolve through the reshuffle: the brute
   spawned last reports `alive @slot 0`, the one spawned third `@slot 1` (order
   preserved by the compaction). D3 holds across both swap-back and cull.

## Verified output

A literal run (`godot --headless --path tests/example_dod_combat_proj`, after a
one-time `--import`):

```
[demo] spawned 6 enemies
[demo] phase 1 — single swap-back kills:
[demo]   sniped id=1 lethal=true
[demo]   sniped id=5 lethal=true
[demo]   survivors: 4
[demo] phase 2 — AoE then one cull() compaction:
[demo]   AoE 12; cull() removed 2 in one pass, 4 -> 2
[demo]   id=1 -> dead
[demo]   id=2 -> dead
[demo]   id=3 -> alive @slot 1
[demo]   id=4 -> dead
[demo]   id=5 -> dead
[demo]   id=6 -> alive @slot 0
```

Every line is a rule paying off: single-removal **swap-back** in phase 1, a single
**compaction** pass for the mass cull in phase 2 (the measured-faster choice for a
subset), and — the subtle one — **ids 3 and 6 still resolving** to their packed
slots after the compaction reshuffled them (D3 holding across the cull).

## What each rule bought, concretely

| Rule | In the fat `Enemy` | Here | The win |
|---|---|---|---|
| D1/D5 | `max_health` etc. on every instance | one shared `EnemyDef` per kind | N enemies share one copy; tune in one place |
| D2 | `_dead` bool + guards | presence in the arrays | no flag to desync; dead aren't in the loop |
| D3 | `_attacker: Node` (dangles) | attacker/entity **id** | freed source resolves to -1, never a wrong object |
| D4 | 30 fields in one object | parallel arrays by access pattern | each system walks only its array |
| D6 | `take_damage()` on the data | `CombatSystem.resolve()` | damage math tested with no SceneTree |
| D7 | armor `if/elif` chain | `armor_mult` table | new armor = new row, not new code |
| D8 | N self-ticking `_physics_process` | one manager `for` | one loop, no per-node dispatch |
| P6 | (n/a — list-shaped) | swap-back `kill()` (single) + write-cursor `cull()` (mass) | O(1) single removal; one-pass compaction for a subset cull, order kept |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_combat_proj --import   # once, builds the class cache
"$GODOT" --headless --path tests/example_dod_combat_proj            # runs the sim
```

The project uses `class_name` globals, so it needs the one-time `--import` to
build the class registry before `--path` can resolve them (same as
`tests/repro_static_init_proj/`). `.godot/` is gitignored; the `.uid` sidecars
are committed.
