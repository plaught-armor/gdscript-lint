class_name SpatialHash
extends RefCounted
## A uniform spatial-hash grid for neighbor / perception queries — the DOD answer
## to "who is near point P?" without testing all N.
##
## D2 — each cell is an existence-set: an agent's index is PRESENT in the bucket
##      for the cell it occupies. The bucket IS the truth; no per-agent "cell" field.
## D4 — agent positions live in one SoA PackedVector2Array; the grid only stores
##      integer indices into it.
## D8 "do less" — a radius query visits only the handful of cells covering the
##      query AABB (≈3×3 when cell_size ≈ radius), not the whole population. Cells
##      touched is independent of N.
##
## Rebuild-per-frame is the canonical pattern when most agents move every frame
## (boids, perception). For mostly-static sets, an incremental move() is cheaper.

var _cell_size: float
var _cells: Dictionary[Vector2i, PackedInt32Array] = { }


func _init(cell_size: float) -> void:
	if cell_size <= 0.0: # boundary precondition (M10) — fail loud, not assert (C12)
		push_error("[SpatialHash] cell_size must be > 0, got %f" % cell_size)
	_cell_size = cell_size


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell_size), floori(p.y / _cell_size))


func build(positions: PackedVector2Array) -> void:
	_cells.clear()
	for i: int in positions.size():
		var c: Vector2i = _cell_of(positions[i])
		var bucket: PackedInt32Array = _cells.get(c, [])
		bucket.append(i)
		_cells[c] = bucket # set back: dict-stored packed arrays are copies, not refs


func cell_count() -> int:
	return _cells.size()


# Fill `out` with the indices of agents within `radius` of `center`. Returns how
# many CELLS were examined — the "do less" number, ~constant regardless of N.
# `positions` MUST be the same array passed to build() — the indices in the cell
# buckets are positions into it (the SoA join key, D4).
func query_radius(positions: PackedVector2Array, center: Vector2, radius: float, out: PackedInt32Array) -> int:
	var r2: float = radius * radius
	var lo: Vector2i = _cell_of(center - Vector2(radius, radius))
	var hi: Vector2i = _cell_of(center + Vector2(radius, radius))
	var cells_examined: int = 0
	for cx: int in range(lo.x, hi.x + 1):
		for cy: int in range(lo.y, hi.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _cells.has(key):
				continue
			cells_examined += 1
			for idx: int in _cells[key]:
				if positions[idx].distance_squared_to(center) <= r2:
					out.append(idx)
	return cells_examined
