class_name GuardManager
extends RefCounted
## Perception as DOD, and a concrete payoff of the corrected D8.
##
## D4/D5 — guard state is SoA: parallel arrays indexed by slot, not a fat Guard
##         node. The sense loop walks _pos; nothing else is dragged through.
## D8 (corrected) — sense() is the INLINE-SoA form: one flat loop over the
##         position array, NO per-guard method call. That is the form measured
##         FASTER than per-node; a manager that called guard.sense() per node
##         would be ~2x slower (see bench_process_centralization_proj).
## D2 — alert state is existence-based: a guard is "alerted" iff it has an entry
##         in _alert_timer, keyed by id. The dict IS the alerted set (the Node
##         group's shape for non-Node entities). No _alerted bool per guard.
## D8 "do less" — decay() iterates ONLY the alerted subset, not all guards. The
##         work that doesn't happen is the win, not a cheaper loop.
## D3 — guards are addressed by stable id; is_alerted(id) answers across systems.

const ALERT_HOLD: float = 2.0

var _next_id: int = 1
var _id: PackedInt64Array = [] # stable id per slot (D3)
var _pos: PackedVector3Array = [] # hot
var _range_sq: PackedFloat32Array = [] # view range squared (avoid per-slot sqrt)
var _alert_timer: Dictionary[int, float] = { } # id -> seconds left (D2 alerted set)


func spawn(pos: Vector3, view_range: float) -> int:
	var id: int = _next_id
	_next_id += 1
	_id.append(id)
	_pos.append(pos)
	_range_sq.append(view_range * view_range)
	return id


func count() -> int:
	return _id.size()


func is_alerted(id: int) -> bool:
	return _alert_timer.has(id)


func alerted_count() -> int:
	return _alert_timer.size()


# D8 inline SoA: flat loop over the position array, no per-guard call. A guard in
# range enters (or refreshes) the alerted set — existence-based (D2). Uses squared
# distance to skip the per-slot sqrt.
func sense(player_pos: Vector3) -> void:
	for slot: int in _id.size():
		if _pos[slot].distance_squared_to(player_pos) <= _range_sq[slot]:
			_alert_timer[_id[slot]] = ALERT_HOLD


# Decay iterates ONLY the alerted subset (doing less). Collect expirations, then
# erase — never add or erase keys mid-iteration (M4); updating values for existing
# keys during iteration is safe (the keyset is unchanged).
func decay(dt: float) -> void:
	var expired: PackedInt64Array = []
	for id: int in _alert_timer:
		var left: float = _alert_timer[id] - dt
		if left <= 0.0:
			expired.append(id)
		else:
			_alert_timer[id] = left
	for id: int in expired:
		_alert_timer.erase(id)
