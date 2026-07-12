# DOD by example: a spatial hash (neighbor queries that do less)

Worked example #5. "Who is near point P?" is the query behind perception, aggro,
flocking, and AoE — and answered naively it's O(N) per query, O(N²) for all-pairs.
A spatial hash makes it cost a **constant handful of cells**, independent of N.
Runnable: [`tests/example_dod_spatial_proj/`](../../tests/example_dod_spatial_proj/),
verified on 4.8.dev.

**In plain terms:** chop the world into a grid of cells, and keep a list of which
agents are in each cell. To find who's near a point, you only look in the few
cells around that point — not at every agent in the game.

---

## The shape

A `SpatialHash` keeps a dictionary from **cell coordinate → list of agent
indices**. The cell is an existence-set (D2): an agent's index is *present* in the
bucket of the cell it occupies — no `cell` field on the agent. Positions live in
one SoA `PackedVector2Array` (D4); the grid stores only integer indices into it.

```gdscript
var _cells: Dictionary[Vector2i, PackedInt32Array] = {}

func build(positions: PackedVector2Array) -> void:
	_cells.clear()                                   # rebuild per frame
	for i: int in positions.size():
		var c: Vector2i = _cell_of(positions[i])
		var bucket: PackedInt32Array = _cells.get(c, [])
		bucket.append(i)
		_cells[c] = bucket    # set back: dict-stored packed arrays are copies, not refs
```

The set-back on the last line is a real gotcha: a `Packed*Array` fetched from a
`Dictionary` is a **value copy**, so `_cells[c].append(i)` would mutate a throwaway.
Get, modify, set back.

The query visits only the cells covering the query AABB — `≈3×3` when the cell
size matches the radius — and refines by squared distance (no `sqrt`):

```gdscript
func query_radius(positions: PackedVector2Array, center: Vector2, radius: float, out: PackedInt32Array) -> int:
	var r2: float = radius * radius
	var lo: Vector2i = _cell_of(center - Vector2(radius, radius))
	var hi: Vector2i = _cell_of(center + Vector2(radius, radius))
	var cells_examined: int = 0
	for cx: int in range(lo.x, hi.x + 1):
		for cy: int in range(lo.y, hi.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _cells.has(key): continue
			cells_examined += 1
			for idx: int in _cells[key]:
				if positions[idx].distance_squared_to(center) <= r2:
					out.append(idx)
	return cells_examined
```

## Verified output

```
[demo] 200 agents over 60x60, cell=5.0 → 98 non-empty cells
[demo] query r=5.0 @ (30,30): examined 7 cells, found 2 within radius (of 200 agents)
[demo] brute-force scan of all 200 agrees: 2 within radius
[demo] grid touched 7 cells vs scanning 200 agents — the 'do less' win
```

The query touched **7 cells** and found the 2 neighbors — a brute-force scan of
all 200 agrees on the answer but pays 200 distance tests. Cells-examined stays
~constant as N grows; that's the win.

## What each rule bought

| Rule | Naive | Here | Win |
|---|---|---|---|
| D2 | scan all N, test each | cell bucket = occupant set | only nearby agents tested |
| D4 | fields on N agent Nodes | one SoA `PackedVector2Array` + index buckets | cache-tight, no Node overhead |
| D8 "do less" | O(N) per query | ~constant cells per query | work independent of N |

---

## Variants & use-cases

The example is a **uniform grid / spatial hash** — the right default for *many
same-sized agents that move every frame*. It is one of several structures, and
for some jobs you shouldn't hand-roll at all.

### Pick the structure by the workload

| Structure | Wins when | Loses when |
|---|---|---|
| **Uniform grid / spatial hash** | same-size agents, ~uniform spread, all moving; rebuild is cheap | clustered population (all in one cell → O(n²) again); wide size variation |
| **Quadtree / octree** | uneven density, mostly static/slow; adapts to empty *and* dense regions | heavy churn — a mover crossing a node bound forces re-link/new-node |
| **Loose octree** | many *dynamic* objects, objects straddling bounds | inflated bounds hurt raycast/SAH quality |
| **BVH (dynamic / dBVT)** | dynamic objects with identity; refit on small moves | static-only or pure raytrace (SAH-built tree wins) — **this is Godot's own physics broadphase** |
| **Sort-and-sweep (SAP)** | objects spread along one axis, smooth motion; near-O(n) via coherence | swarms/clusters → endpoint-swap storms degrade super-linear |
| **Hierarchical grid** | mixed object sizes (each lands at the level it fits) | small size variance → plain grid is simpler |
| **BSP / k-d** | static geometry, build-once query-millions (FPS world) | dynamic → must rebuild |

Sources: [Nystrom — Spatial Partition](https://gameprogrammingpatterns.com/spatial-partition.html),
[Korth — collision & spatial indexes](https://kortham.net/posts/collision-detect-and-spatial-indexes/),
[Godot physics progress #1 (lawnjelly's dBVT)](https://godotengine.org/article/physics-progress-report-1/).
Rule of thumb: flat structures = cheaper *updates*, hierarchical = better for
empty+dense; broadphase favors flat/refit because it rebuilds every tick.

### Cell sizing & update strategy

- **Cell size ≈ query radius** (or ≈ 2× agent radius for contact) so a query
  touches a constant `~3×3` (2D) / `~3×3×3` (3D) footprint regardless of N
  ([Cincotti — spatial hash maps](https://carmencincotti.com/2022-10-31/spatial-hash-maps-part-one/)).
  Too large → false positives; too small → each agent straddles many cells.
- **Rebuild-per-frame** (this example) when most agents move every frame (boids,
  perception). **Incremental `move()`** (unlink old cell, link new) when most are
  static and a few move — pay per actual move, not per frame.
- **Hashing unbounded space**: key cells by an integer hash (`(xi*92837111) ^
  (yi*689287499) mod TABLE`) or Morton/Z-order for cache-friendly ranges, instead
  of a `Vector2i` key, when the world has no fixed bounds.

### Pitfalls

- **Agent spans multiple cells** → insert into all touched cells and **dedupe
  candidate ids per query**, or use a loose octree (cells overlap, one home).
- **Clustered population** collapses a uniform grid back to O(n²) inside the hot
  cell → switch to a quadtree (adapts to density) or cap-per-cell.
- **Hash collisions** (two distant cells, one bucket) → store the cell coord with
  each id and discard mismatches.
- **`get_nodes_in_group()` in the query loop** allocates per call (D2a) — cache
  the set; this is why the example stores indices, not re-queries the tree.

### Don't hand-roll it when Godot already has it

Godot's `PhysicsServer` **already maintains a dynamic-BVH broadphase**. Reach for
it before a custom grid:

| Need | Use |
|---|---|
| physics collision pairs / contacts | `RigidBody`/`CharacterBody` — you won't beat the engine's dBVT |
| perception/aggro, ≤ ~50 agents | `Area2D/3D` + `body_entered` |
| coarse perception without exact shape | `area_set_param(rid, AREA_PARAM_BROADPHASE_ONLY, true)` — AABB-only, "much faster" |
| one-shot "what's in this radius/ray?" | `PhysicsDirectSpaceState.intersect_shape/ray` with `max_results` |

A **custom grid pays off** at *hundreds–thousands of lightweight agents that don't
need full physics* — boids/flocking (k-nearest per agent every frame), perception
at scale (forum reports stock Godot agents tanking past ~150 on screen), hundreds
of concurrent AoE overlaps, minimap/culling. There the per-`Area` broadphase churn
and per-Node `_physics_process` lose to one manager iterating the grid cell-by-cell
(D8). Sources: [Godot proposal #2714 (AABB-only Area)](https://github.com/godotengine/godot-proposals/issues/2714),
[Godot forum — boids/Pikmin perf](https://forum.godotengine.org/t/boid-behavior-and-optimization-for-a-pikmin-like/71608),
[PhysicsDirectSpaceState3D docs](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html).

### Use-case sheet

| Use-case | Default | Note |
|---|---|---|
| physics collision broadphase | engine dBVT | don't reimplement |
| perception/aggro ≤ 50 | `Area3D` signal | minimal code |
| perception/aggro 100s–1000s | custom uniform grid + manager tick | sidesteps per-Area churn |
| boids / flocking | spatial hash, cell = neighbor radius, rebuild/tick | 3×3 footprint per agent |
| AoE (one-shot, small N) | `intersect_shape` + `max_results` | engine BVH handles it |
| AoE (100s concurrent) | custom grid, per-cell batch | collapses N×M queries |
| minimap / "what's in rect" | quadtree (static) or grid (mixed) | no physics narrowphase needed |
| open-world streaming | loose octree / hierarchical grid | size variance + dynamic insert |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_spatial_proj --import   # once
"$GODOT" --headless --path tests/example_dod_spatial_proj
```
