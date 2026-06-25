class_name ProjectilePool
extends RefCounted
## Object pooling as DOD (P21): a fixed bank of slots reused forever — never a
## per-frame `.new()` / `free()`. Composes three threads:
##
## D4/D5 — projectile state is SoA: parallel packed arrays of fixed capacity.
## free-list — `_free` is a stack of unused slot indices. spawn() pops, despawn
##             pushes: O(1) acquire/release, no scan for a free slot.
## D8 + dead-removal — tick() walks only the DENSE `_active` list (not all CAP
##             slots), advances each inline, and on expiry returns the slot to the
##             pool via swap-back removal from `_active` (P6: O(1), order-agnostic
##             — a pool doesn't care about projectile order).
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


# D8 — one inline pass over the active set. Expired projectiles return their slot
# to the free stack and are swap-back removed from _active (don't advance i; the
# swapped-in slot is re-checked next iteration). Condition-while, not a countdown.
func tick(dt: float) -> void:
	var i: int = 0
	while i < _active.size():
		var slot: int = _active[i]
		_ttl[slot] -= dt
		if _ttl[slot] <= 0.0:
			_free.append(slot) # return the slot to the pool — reused on next spawn
			_active[i] = _active[_active.size() - 1]
			_active.resize(_active.size() - 1)
		else:
			_pos[slot] = _pos[slot] + _vel[slot] * dt
			i += 1


func active_count() -> int:
	return _active.size()


func free_count() -> int:
	return _free.size()
