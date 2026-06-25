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
# Naive — allocate + free a Node per shot (P21: churn in the hot path).
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
  (not all CAP), advances each inline, and culls the expired in one **write-cursor
  compaction** pass: survivors compact toward cursor `w`, expired slots return to
  `_free`, and a single `resize` drops the tail. This is the
  [removing-dead-entities](note-removing-dead-entities.md) note's *subset-cull*
  shape — it beats repeated swap-back when more than one slot expires in a pass,
  and it's a clean forward `for`, not a hand-rolled `while`:

```gdscript
func tick(dt: float) -> void:
	var w: int = 0                          # write cursor: next survivor slot
	for r: int in _active.size():
		var slot: int = _active[r]
		_ttl[slot] -= dt
		if _ttl[slot] <= 0.0:
			_free.append(slot)              # expired → slot back to the pool
		else:
			_pos[slot] = _pos[slot] + _vel[slot] * dt
			_active[w] = slot               # keep: compact toward the front
			w += 1
	_active.resize(w)                       # drop the culled tail, one resize
```

The invariant `_free.size() + _active.size() == CAP` holds across every op — no
slot is ever leaked or double-freed, and the SoA arrays never grow.

## Verified output

```
[demo] CAP=8, free=8
[demo] spawned 5 → slots [0, 1, 2, 3, 4], active=5 free=3
[demo] after 1.2s tick → active=4 free=4
[demo] spawned 2 more → reused slots [0, 5] (were freed above)
[demo] active=6 free=2 (CAP still 8, no growth)
[demo] drained → active=0 free=8
[demo] over-spawned CAP+ → exhausted spawn returns -1
```

The tell is the `spawned 2 more` line: the next spawn hands back **slot 0** — the
one just freed — not a ninth slot. The bank is fixed; the indices cycle.

## What each rule bought

| Rule | Naive | Here | Win |
|---|---|---|---|
| P21 | `.new()` / `free()` per shot | fixed bank, reused slots | no per-frame alloc/GC churn |
| free-list | scan for a free slot | `_free` stack pop/push | O(1) acquire/release |
| D4/D5 | fields on N `Bullet` nodes | SoA packed arrays | cache-tight, no `Node` overhead |
| D8 | N self-ticking bullets | one `for` over `_active` | inline, only live slots |
| dead-removal | — | write-cursor compaction of `_active` | one pass + one resize; beats repeated swap-back for a subset cull |

## Variants & use-cases

The example is one point in a wide space. Pick by the use-case, and **profile
before pooling at all**.

### Do you even need it?

GDScript objects are **reference-counted, not garbage-collected** — there are no
GC pauses for pooling to amortize, and Godot 4 made node instantiation much
faster than Godot 3, retiring many old "you must pool" recipes. The engine lead's
default advice is *"you don't really need to do pooling"*
([reduz](https://x.com/reduzio/status/1073284242086551552),
[GDQuest](https://www.gdquest.com/tutorial/godot/design-patterns/intro-to-design-patterns/)).
Pool only when a profiler points at instantiation — high-frequency, short-lived
objects (bullet hells, swarms, repeated VFX). And often the bigger win is to skip
Nodes entirely: `MultiMeshInstance` + a `PackedVector2Array` of transforms, or a
server-side bullet system, beats a Node pool at scale
([qurobullet](https://github.com/quinnvoker/qurobullet)).

### Exhaustion policy (Nystrom's four)

This example returns `-1` (silent drop). That's one of four
([Game Programming Patterns — Object Pool](https://gameprogrammingpatterns.com/object-pool.html)):

| Policy | Fits | Example here |
|---|---|---|
| **Prevent** (size for peak) | known bounded load | size `CAP` from peak concurrent × lifetime × rate |
| **Drop** the new request | particles/VFX — one missed puff is invisible | our `return -1` |
| **Replace oldest/quietest** | audio voices, bullet-hell ("a snapped bullet beats a stutter") | evict `_active[0]` instead of refusing |
| **Grow** (instantiate + `push_warning`) | catch undersizing in playtest | append a slot on miss |

### Stale-handle safety: generational indices

A raw slot index has the **ABA problem**: hold index 5 (Alice), Alice expires,
Bob reuses slot 5 — your index now silently points at Bob. (Same class as Godot's
own `instance_from_id` reuse, [#32383](https://github.com/godotengine/godot/issues/32383),
this corpus's D3/C8.) For handles that **outlive** their referent (an AI target, a
saved reference), pack a **generation** alongside the index: a 64-bit handle =
`index | (generation << 32)`, a `PackedInt64Array` of per-slot generations bumped
on free, and an `is_valid(handle)` check at every read
([generational indices](https://www.studyplan.dev/structure-of-arrays/generational-indices)).
For one-frame transient refs (our example), skip it — the overhead exceeds the
bug surface.

### Pooling Nodes (not pure data)

If you must pool `Node`s, the reset discipline is the hard part — **`_ready()`
does NOT re-fire** on reuse, so a `reset()` / `on_spawn()` is mandatory, and it
must clear *every* mutable field (position, velocity, `modulate`, `scale`, timers,
AI state, **signal connections**), or stale state leaks into the next user
([forum](https://forum.godotengine.org/t/what-is-the-best-way-to-do-object-pooling/28960),
[reset gotchas](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)).
"Inert while pooled" needs three toggles, not one: `set_process(false)` +
`set_physics_process(false)` + `collision_layer = collision_mask = 0` (and
`freeze = true` for a `RigidBody`, which ignores `set_physics_process`). Keep
pooled nodes parented to one `PoolRoot` and toggle them — don't churn the tree
with `remove_child`/`add_child`. Pre-warm the whole bank at level load so the
spike lands on the loading screen. **The pure-data SoA pool above sidesteps all of
this** — no `_ready`, no signals, no per-node toggles; it's the cheapest pool when
the entity doesn't need to be a Node.

### Per use-case

| Use-case | Variant | Note |
|---|---|---|
| Bullets | data/`BulletServer` or MultiMesh; replace-oldest | hand-pooled Nodes only at low counts |
| Particles | **don't hand-pool** — `GPUParticles` `one_shot` + `restart()` | pool the *emitter* if you need many sites/sec |
| Enemies | manager-local Node pool, `set_physics_process(false)` while idle | only if cheap + high spawn rate (D8) |
| Audio | `AudioStreamPlayer.max_polyphony` (4.0+) obviates most | else replace-oldest/quietest voice |
| UI list (virtualized) | visible-window pool, recycle off-screen rows | size = visible count; can't exhaust |
| Tween/Timer | pool-of-one (`stop()`/`start()` reuse) | per-frame `create_tween()`/`Timer.new()` churns |

Manager-local pools (scoped to a level, die with the manager) are the clean
default; a global autoload pool only when consumers are spread across scenes
(UI, audio) — at the cost of harder cross-level cleanup.

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_pool_proj --import   # once
"$GODOT" --headless --path tests/example_dod_pool_proj
```
