# gdlint: disable-file
class_name Room
extends Node
## D2b — the owner that sees every spawn and death holds the alive-set DIRECTLY,
## in a typed Array scoped to this room. No tree-global &"alive" group:
## "alive in THIS room" is a bare _alive.size() — O(1), no global name to collide,
## no whole-tree sweep. The locality a tree-scattered group cannot give.

var room_id: int = 0
var _alive: Array[Enemy] = [] # owner-held membership (D2b), scoped to this room


func spawn(enemy_id: int) -> Enemy:
	var e: Enemy = Enemy.new()
	e.id = enemy_id
	e.name = "Enemy%d" % enemy_id
	add_child(e)
	_alive.append(e) # the owner sees the add — no group needed
	return e


func kill(enemy_id: int) -> void:
	# The set is unordered, so remove in O(1) by swap-back: overwrite the dead slot
	# with the last element and drop the tail — never remove_at's O(n) shift (P6 /
	# the removing-dead-entities note). A real project reaches for the SwapBackArray
	# addon here; inlined so the example stays dependency-free.
	for i: int in _alive.size():
		if _alive[i].id == enemy_id:
			_alive[i].queue_free()
			_alive[i] = _alive[_alive.size() - 1] # last over the hole (self if i is last)
			_alive.resize(_alive.size() - 1) # drop the tail, O(1)
			return


func enemies() -> Array[Enemy]:
	# Snapshot for the demo's read-out — hand back a copy, never the internal
	# array, so a caller can't mutate the room's owned set behind its back.
	return _alive.duplicate()


func alive_count() -> int:
	return _alive.size() # scoped, O(1), no global sweep, no global name


func alive_ids() -> PackedInt64Array:
	var out: PackedInt64Array = []
	out.resize(_alive.size()) # P7 — pre-size, no per-append realloc
	for i: int in _alive.size():
		out[i] = _alive[i].id
	return out
