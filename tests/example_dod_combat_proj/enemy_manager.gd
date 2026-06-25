class_name EnemyManager
extends RefCounted
## The HOT side, and the heart of the example. Five rules compose here:
##
## D4 — state is split into parallel arrays indexed by SLOT, not bundled into a
##      fat Enemy object. The physics-ish loop walks _pos_x; combat walks
##      _health; neither drags the other's fields through cache.
## D5 — each slot stores only a Kind index (_kind). The cold per-kind constants
##      (max health, speed, armor) live once in EnemyRegistry.defs, shared by all
##      instances of that kind — not copied onto every slot.
## D2 — existence-based: a slot's PRESENCE in the arrays *is* "alive". There is no
##      _dead bool; death is removal. is-alive == has-a-slot.
## P6 — two ways the dead leave (bible/removing-dead-entities.md): kill(slot) is
##      swap-back (O(1), one removal); cull() is write-cursor compaction (one pass,
##      keeps order, for mass removal). Measured: compaction wins a subset cull.
## D8 — one tick() loops every slot once. Entities do not self-process; the
##      manager owns the loop.
## D3 — a stable id->slot map lets other systems hold an integer id across the
##      swap-back reshuffle; slot_of() resolves it to a live slot or -1 (dead).

var _next_id: int = 1
var _id: PackedInt64Array = [] # stable entity id per slot (D3)
var _kind: PackedInt32Array = [] # Kind as int — D5 cold ref. Packed* can't carry
# the enum type (the D10a wire-format exception); get_def's Kind param takes the int.
var _health: PackedInt32Array = [] # hot
var _pos_x: PackedFloat32Array = [] # hot (1-D position keeps the SoA demo terse)
var _slot_of: Dictionary[int, int] = { } # id -> slot index (D3 resolve)


func spawn(kind: EnemyRegistry.Kind, x: float) -> int:
	var id: int = _next_id
	_next_id += 1
	var def: EnemyDef = EnemyRegistry.get_def(kind)
	_id.append(id)
	_kind.append(kind)
	_health.append(def.max_health)
	_pos_x.append(x)
	_slot_of[id] = _id.size() - 1
	return id


func count() -> int:
	return _id.size()


func def_at(slot: int) -> EnemyDef:
	return EnemyRegistry.get_def(_kind[slot])


func health_at(slot: int) -> int:
	return _health[slot]


func pos_at(slot: int) -> float:
	return _pos_x[slot]


# External lookup of a possibly-dead id — the one place .get(k, default) is right
# (the id may legitimately be absent after a kill). Returns -1 for dead/unknown.
func slot_of(id: int) -> int:
	return _slot_of.get(id, -1)


func apply_damage(slot: int, dealt: int) -> void:
	_health[slot] -= dealt


# D8 — one batched pass advances every live enemy toward x = 0 at its kind speed.
func tick(dt: float) -> void:
	for slot: int in _id.size():
		var def: EnemyDef = EnemyRegistry.get_def(_kind[slot])
		var stepped: float = _pos_x[slot] - def.speed * dt
		_pos_x[slot] = maxf(0.0, stepped)


# P6 — swap-back removal. Move the last slot into the hole, shrink every parallel
# array by one, and keep the id->slot map consistent for the moved entity.
func kill(slot: int) -> void:
	var dead_id: int = _id[slot]
	var last: int = _id.size() - 1
	if slot != last:
		var moved_id: int = _id[last]
		_id[slot] = _id[last]
		_kind[slot] = _kind[last]
		_health[slot] = _health[last]
		_pos_x[slot] = _pos_x[last]
		_slot_of[moved_id] = slot
	_id.resize(last)
	_kind.resize(last)
	_health.resize(last)
	_pos_x.resize(last)
	_slot_of.erase(dead_id)


# Mass cull — write-cursor compaction across every SoA array in one pass, keeping
# order, one resize at the end. Use this to drop MANY dead at once (e.g. after an
# AoE); kill(slot) above stays for a single known removal. Measured faster than
# repeated swap-back for a subset cull (bible/removing-dead-entities.md). Removes
# every slot with health <= 0; returns how many were removed.
func cull() -> int:
	var n: int = _id.size()
	var w: int = 0 # write cursor
	for r: int in n: # read cursor — touch each slot exactly once
		if _health[r] > 0:
			if w != r:
				_id[w] = _id[r]
				_kind[w] = _kind[r]
				_health[w] = _health[r]
				_pos_x[w] = _pos_x[r]
			_slot_of[_id[w]] = w # survivor's id now points at its packed slot
			w += 1
		else:
			_slot_of.erase(_id[r]) # dead: drop the id->slot entry
	_id.resize(w)
	_kind.resize(w)
	_health.resize(w)
	_pos_x.resize(w)
	return n - w
