class_name ProjectilePool
extends RefCounted
## Object pooling as DOD (P21): a fixed bank of slots reused forever — never a
## per-frame `.new()` / `free()`. Composes three threads:
##
## D4/D5 — projectile state is SoA: parallel packed arrays of fixed capacity.
## free-list — `_free` is a stack of unused slot indices. spawn() pops, despawn
##             pushes: O(1) acquire/release, no scan for a free slot.
## D8 + dead-removal — tick() walks only the DENSE `_active` list (not all CAP
##             slots) in one WRITE-CURSOR compaction pass: survivors advance and
##             compact toward cursor `w`, expired slots return to `_free`, one
##             `resize(w)` drops the tail. Beats repeated swap-back for a subset
##             cull (the removing-dead-entities note) and fuses the survivor
##             update into the same pass.
##
## "Spawn" reuses a freed slot index, so the SoA arrays never grow or reallocate.

const CAP: int = 8 # tiny so the demo shows exhaustion + reuse; real pools are larger

var _pos: PackedVector2Array = [] # hot
var _vel: PackedVector2Array = [] # hot
var _ttl: PackedFloat32Array = [] # hot: seconds left; <= 0 means expired
var _free: PackedInt32Array = [] # stack of free slot indices
var _active: PackedInt32Array = [] # dense list of active slot indices (D8 loop)


func _init() -> void:
	_pos.resize(CAP)
	_vel.resize(CAP)
	_ttl.resize(CAP)
	_free.resize(CAP)
	for i: int in CAP:
		_free[i] = CAP - 1 - i # 0 ends up on top of the stack


func spawn(pos: Vector2, vel: Vector2, ttl: float) -> int:
	if _free.is_empty():
		return -1 # pool exhausted — caller decides (drop, or grow the bank)
	var slot: int = _free[_free.size() - 1]
	_free.resize(_free.size() - 1) # pop the free stack — O(1), no alloc
	_pos[slot] = pos
	_vel[slot] = vel
	_ttl[slot] = ttl
	_active.append(slot)
	return slot


# D8 + dead-removal — one inline forward pass, WRITE-CURSOR compaction (the
# removing-dead-entities note): survivors compact toward cursor w, expired slots
# return to the free stack. One pass, one resize — beats repeated swap-back for a
# subset cull, and each survivor's TTL/position advance happens in the same pass.
func tick(dt: float) -> void:
	var w: int = 0 # write cursor: next survivor position
	for r: int in _active.size():
		var slot: int = _active[r]
		_ttl[slot] -= dt
		if _ttl[slot] <= 0.0:
			_free.append(slot) # expired → slot back to the pool, not kept
		else:
			_pos[slot] = _pos[slot] + _vel[slot] * dt
			_active[w] = slot # keep: compact toward the front
			w += 1
	_active.resize(w) # drop the culled tail in one resize


func active_count() -> int:
	return _active.size()


func free_count() -> int:
	return _free.size()
