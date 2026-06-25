# DOD by example: a perception system (existence-based + the corrected D8)

A second worked subsystem (after [the combat example](ex-combat.md)), chosen
because perception is where two rules earn their keep most visibly: **existence-
based state (D2)** and the **corrected D8** — a manager wins by *doing less* and by
working *flat data inline*, not by looping nodes and calling a method per entity.
Runnable: [`tests/example_dod_perception_proj/`](../tests/example_dod_perception_proj/),
verified on 4.8.dev.

**In plain terms:** guards notice a player who walks near them, and stay alert for
a couple of seconds after. Instead of a `_alerted` flag on every guard and an
update function on each, there's *one list of who's currently alerted* and *one
flat loop that checks distances* — the data-oriented way.

---

## The naive shape

```gdscript
class_name Guard extends Node3D
var view_range: float = 3.0
var _alerted: bool = false        # a flag on every guard
var _alert_timer: float = 0.0     # a timer on every guard, even the 99% idle ones

func _physics_process(delta):     # N self-ticking sensors
    if global_position.distance_to(player.global_position) <= view_range:
        _alerted = true
        _alert_timer = 2.0
    elif _alerted:
        _alert_timer -= delta
        if _alert_timer <= 0.0: _alerted = false
```

Smells: a `_alerted` bool to keep in sync (**D2**); an `_alert_timer` carried by
every guard even though almost none are alerted (**D5** cold-on-hot); N self-
ticking sensors each calling into the player (**D8**); and "who's alerted?" needs
a scan of all guards.

## The data-oriented shape

One `GuardManager` owns SoA arrays; alert state is a **dictionary keyed by id** —
the dict *is* the alerted set (the Node-group shape for non-Node entities, D2):

```gdscript
var _id: PackedInt64Array = []        # stable id per slot (D3)
var _pos: PackedVector3Array = []     # hot
var _range_sq: PackedFloat32Array = []# squared range — skip the per-slot sqrt
var _alert_timer: Dictionary[int, float] = {}   # id -> seconds left == the alerted set
```

**Sensing is the inline-SoA form** — one flat loop over the position array, *no
per-guard method call* (this is the form the D8 bench measured *faster* than
per-node; a manager calling `guard.sense()` per node would be ~2× slower):

```gdscript
func sense(player_pos: Vector3) -> void:
	for slot: int in _id.size():
		if _pos[slot].distance_squared_to(player_pos) <= _range_sq[slot]:
			_alert_timer[_id[slot]] = ALERT_HOLD   # enter/refresh the alerted set
```

**Decay touches only the alerted subset** — the corrected D8's real win is *doing
less*, not a cheaper loop. The 99% of guards who aren't alerted have no entry and
are never visited. (Collect expirations, then erase — never add/remove keys mid-
iteration, M4; updating values in place is fine.)

```gdscript
func decay(dt: float) -> void:
	var expired: PackedInt64Array = []
	for id: int in _alert_timer:
		var left: float = _alert_timer[id] - dt
		if left <= 0.0: expired.append(id)
		else: _alert_timer[id] = left
	for id: int in expired:
		_alert_timer.erase(id)

func is_alerted(id: int) -> bool: return _alert_timer.has(id)   # O(1), no scan
```

## Verified output

The player walks `x = 0..20` past six guards; the alerted set tracks the moving
window, then drains over the 2 s hold once the player is gone:

```
[demo] 6 guards; player walks x=0..20
[demo] x= 6  alerted=3  ids=[1, 2, 3]
[demo] x= 7  alerted=3  ids=[2, 3, 4]      # guard 1 decayed out as 4 entered
[demo] x=14  alerted=3  ids=[4, 5, 6]
[demo] x=20  alerted=1  ids=[6]
[demo] player gone; draining alerted set:
[demo]   +0.5s  alerted=1
[demo]   +1.5s  alerted=0                  # 2s hold elapsed, set empty
```

Every line is existence-based: the count *is* the dictionary size, and the
membership slides as the player moves — no flags, no per-guard timers, no scan.

## What each rule bought

| Rule | Fat `Guard` | Here | Win |
|---|---|---|---|
| D2 | `_alerted` bool + `_alert_timer` on all | entry in `_alert_timer` keyed by id | the dict is the alerted set; `is_alerted` is O(1), no scan |
| D5 | timer on every guard | only alerted have a timer entry | idle guards carry zero alert state |
| D4 | fields on one node | SoA arrays on the manager | sense walks only `_pos`/`_range_sq` |
| D8 (sense) | N self-ticking sensors | one inline flat loop, no per-guard call | the *fast* form (bench: ~2× over manager-of-nodes) |
| D8 (decay) | every guard ages its timer | only the alerted subset is visited | the work that doesn't happen is the win |
| D3 | live player/guard refs | ids; `is_alerted(id)` | answers across systems, survives frees |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_perception_proj --import   # once
"$GODOT" --headless --path tests/example_dod_perception_proj
```
