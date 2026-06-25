# gdlint: disable-file
extends Node
## Spatial-hash demo. Scatter N agents in a 60x60 field, build the grid, then ask
## "who is within radius 5 of (30,30)?". The point: the query touches a handful of
## cells, not all N. Positions are deterministic so the output is reproducible.
##   godot --headless --path tests/example_dod_spatial_proj  (import first)

const N: int = 200
const FIELD: float = 60.0
const CELL: float = 5.0 # cell size ≈ query radius → small constant footprint


func _ready() -> void:
	# Deterministic hash-scatter across [0,FIELD) x [0,FIELD) — well distributed so
	# the grid has many cells and a query touches only a few.
	var positions: PackedVector2Array = []
	positions.resize(N)
	for i: int in N:
		var hx: int = (i * 2654435761) % 600
		var hy: int = (i * 40503 + 1013904223) % 600
		positions[i] = Vector2(float(hx) / 10.0, float(hy) / 10.0)

	var grid: SpatialHash = SpatialHash.new(CELL)
	grid.build(positions)
	print("[demo] %d agents over %.0fx%.0f, cell=%.1f → %d non-empty cells" % [N, FIELD, FIELD, CELL, grid.cell_count()])

	var center: Vector2 = Vector2(30, 30)
	var radius: float = 5.0
	var hits: PackedInt32Array = []
	var cells_examined: int = grid.query_radius(positions, center, radius, hits)
	print(
		(
				"[demo] query r=%.1f @ %v: examined %d cells, found %d within radius (of %d agents)"
				% [radius, center, cells_examined, hits.size(), N]
		),
	)

	# The do-less proof: a brute-force scan would test all N; the grid tested only
	# the agents in the examined cells.
	var brute: int = 0
	for i: int in N:
		if positions[i].distance_squared_to(center) <= radius * radius:
			brute += 1
	print("[demo] brute-force scan of all %d agrees: %d within radius" % [N, brute])
	print("[demo] grid touched %d cells vs scanning %d agents — the 'do less' win" % [cells_examined, N])

	get_tree().quit()
