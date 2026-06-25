# DOD by example: an object pool (free-list + slot reuse)

Worked example #4. Pooling is where "don't allocate in the hot loop" (P21) meets
the dead-removal thread: a fixed bank of slots is **reused forever** — a spawn
recycles a freed slot index instead of calling `.new()`, and an expiry returns
the slot rather than `free()`-ing anything. Runnable:
[`tests/example_dod_pool_proj/`](../tests/example_dod_pool_proj/), verified on
4.8.dev.

**In plain terms:** instead of creating a bullet object when you fire and
destroying it when it dies (slow, churns memory), you keep a fixed set of bullet
"slots" and hand out free ones, taking them back when a bullet expires. Same
slots, over and over.

---

## The naive shape

```gdscript
func fire():
    var b := Bullet.new()        # allocate every shot
    add_child(b)
func _on_bullet_expired(b):
    b.queue_free()               # free every death — churn + GC pressure
```

At hundreds of shots/second this allocates and frees hundreds of `Node`s/second
— the exact "alloc in the hot path" P21 warns against.

## The pooled shape

A `ProjectilePool` owns fixed-capacity SoA arrays plus two index lists:

```gdscript
const CAP: int = 8
var _pos: PackedVector2Array = []  ; var _vel: PackedVector2Array = []
var _ttl: PackedFloat32Array = []                 # SoA hot state (D4/D5)
var _free: PackedInt32Array = []                  # stack of unused slot indices
var _active: PackedInt32Array = []                # dense list of live slots (D8)
```

- **`_free` is a free-list** — a stack of slot indices nobody's using. `spawn`
  pops the top, `tick` pushes a slot back on expiry. O(1) acquire/release, no
  scan for an empty slot:

```gdscript
func spawn(pos: Vector2, vel: Vector2, ttl: float) -> int:
	if _free.is_empty(): return -1          # exhausted — caller drops or grows
	var slot: int = _free[_free.size() - 1]
	_free.resize(_free.size() - 1)          # pop — O(1), no alloc
	_pos[slot] = pos; _vel[slot] = vel; _ttl[slot] = ttl
	_active.append(slot)
	return slot
```

- **`_active` is the dense iterate-set** — `tick` walks *only* the live slots
  (not all CAP), advances each inline, and on expiry returns the slot to `_free`
  **and swap-back removes it from `_active`** (P6 — O(1), order irrelevant for a
  pool). This is the dead-removal pattern, in-loop:

```gdscript
func tick(dt: float) -> void:
	var i: int = 0
	while i < _active.size():                # condition-while, not a countdown
		var slot: int = _active[i]
		_ttl[slot] -= dt
		if _ttl[slot] <= 0.0:
			_free.append(slot)               # slot back to the pool — reused next spawn
			_active[i] = _active[_active.size() - 1]
			_active.resize(_active.size() - 1)   # swap-back; don't advance i
		else:
			_pos[slot] = _pos[slot] + _vel[slot] * dt
			i += 1
```

The invariant `_free.size() + _active.size() == CAP` holds across every op — no
slot is ever leaked or double-freed, and the SoA arrays never grow.

## Verified output

```
[demo] CAP=8, free=8
[demo] spawned 5 → slots [0, 1, 2, 3, 4], active=5 free=3
[demo] after 1.2s tick → active=4 free=4          # one expired, slot returned
[demo] spawned 2 more → reused slots [0, 5]        # slot 0 RECYCLED, no new storage
[demo] active=6 free=2 (CAP still 8, no growth)
[demo] drained → active=0 free=8
[demo] over-spawned CAP+ → exhausted spawn returns -1
```

The tell is line 4: the next spawn hands back **slot 0** — the one just freed —
not a ninth slot. The bank is fixed; the indices cycle.

## What each rule bought

| Rule | Naive | Here | Win |
|---|---|---|---|
| P21 | `.new()` / `free()` per shot | fixed bank, reused slots | no per-frame alloc/GC churn |
| free-list | scan for a free slot | `_free` stack pop/push | O(1) acquire/release |
| D4/D5 | fields on N `Bullet` nodes | SoA packed arrays | cache-tight, no `Node` overhead |
| D8 | N self-ticking bullets | one `while` over `_active` | inline, only live slots |
| P6 | — | swap-back from `_active` | O(1) return-to-pool, no shift |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_pool_proj --import   # once
"$GODOT" --headless --path tests/example_dod_pool_proj
```
