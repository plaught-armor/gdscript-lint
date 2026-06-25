# Removing dead entities from a list

Existence-based processing (D2) says the dead shouldn't be in the loop. But how
do you *get them out* of a manager-owned `Array` / `Packed*Array` each frame? The
choice matters, and the obvious answer — "swap-back, it's O(1)" — is right for one
removal and **wrong for culling a whole subset**. Measured below
(`bench_dead_removal.gd`, 4.8.dev).

**In plain terms:** when some entities die, you have to compact the list. Pulling
each dead one out individually is slow if many died; making a single clean pass
that keeps the survivors is faster. And the "easy" way (`remove_at` in a loop) is
the slowest of all.

---

## Two different operations

Don't conflate them — they have different best answers:

- **Remove ONE element, by index** (this specific entity just died). → **swap-back**:
  overwrite the slot with the last element, shrink by one. O(1). Order lost. This
  is the combat example's `kill(slot)`.
- **Remove ALL dead, in one pass** (cull the frame's casualties). → **compact**:
  a single forward pass keeping survivors, one resize at the end. O(n). Order kept.

The trap is reaching for repeated swap-back (or worse, `remove_at`) to do the
second job.

## The four strategies, measured

Cull one pass over an N-element list; "dead" is intrinsic to the value so every
strategy removes the same set from a fresh copy. µs, best-of-9, 4.8.dev:

| N | dead % | swap-back | **compact** | rebuild | `remove_at` per dead |
|---|---|---|---|---|---|
| 10,000 | 50% | 485 | **284** | 250 | **1,079** |
| 10,000 | 5% | 348 | **329** | 289 | 411 |
| 1,000 | 50% | 47 | **28** | 24 | 43 |

- **`compact` (write-pointer) wins**, ~1.7× over swap-back at a high death rate,
  and it *keeps order*. It touches each element exactly once and resizes once.
- **swap-back is slower for mass cull** than you'd expect: it re-examines each
  swapped-in element (often itself dead, so re-swapped) and shrinks per removal.
  Its O(1) is per *single* removal — culling a fraction is not that.
- **`remove_at` per dead is the O(n·k) trap** — 1,079 µs at 50%, ~4× compact.
  Each `remove_at(i)` shifts the whole tail (this is P6 one element in from the
  front).
- **rebuild** (append survivors to a *new* array) ties compact on time but
  allocates a second array — use compact's in-place form unless you need the
  original preserved.

## The write-pointer compaction (the one to reach for)

Single forward pass, in place, order-preserving, no dead-list, no per-element
resize. A read cursor scans; a write cursor packs survivors down:

```gdscript
# Compact in place: keep survivors, drop the dead, one resize at the end.
func cull(a: PackedInt32Array) -> void:
	var w: int = 0
	for r: int in a.size():            # typed for (H2); read cursor
		if not _is_dead(a[r]):
			a[w] = a[r]                # pack survivor down to the write cursor
			w += 1
	a.resize(w)                        # one resize drops the tail of dead slots
```

For SoA (D4) — parallel arrays sharing the slot index — run the same write cursor
across *all* the arrays at once, so a survivor's position/health/id stay aligned:

```gdscript
func cull() -> void:
	var w: int = 0
	for r: int in _id.size():
		if _alive(_id[r]):
			_id[w] = _id[r]; _pos[w] = _pos[r]; _health[w] = _health[r]
			w += 1
	_id.resize(w); _pos.resize(w); _health.resize(w)
```

## Removing while iterating — the M4 trap

Whatever the strategy, **don't add or erase from the list you're iterating** — it
invalidates the iteration (M4). Three safe shapes:

- **Compact** (above) — the read/write cursors *are* a safe single pass; nothing
  is removed mid-iteration, the tail is dropped after. Prefer this.
- **Deferred** — collect the dead in a pass, remove them in a second pass. This is
  the perception example's `decay()`: `expired.append(id)` then `erase`. Needed
  when the container is a `Dictionary` (no write-cursor compaction).
- **Backward swap-back** — if you must swap-remove in one pass over an array,
  iterate high→low so a swapped-in element you've already passed isn't re-tested
  incorrectly. (Still loses order; still slower than compact for mass cull.)

## Decision

| Situation | Use | Why |
|---|---|---|
| one entity dies, by known index | **swap-back** | O(1), no shift (combat `kill(slot)`) |
| cull all dead each frame, order irrelevant | **compact** | O(n) one pass, beats repeated swap-back |
| cull all dead, order matters | **compact** | same cost, and it *keeps* order |
| dead live in a `Dictionary` | **deferred** (collect → erase) | no write-cursor over a dict (perception `decay`) |
| anything | **never `remove_at`/`pop_front` in a loop** | O(n·k); the P6 trap |

A nuance on `Array.filter()`: the *method* (`a.filter(func(x): ...)`) pays a
`Callable` per element and returns an **untyped** Array (C3, [#72566](https://github.com/godotengine/godot/issues/72566)) —
slower than the hand-written compaction and a typing footgun. The "rebuild" row
above is a hand loop, not `.filter()`. Reach for the write cursor.

## Run it

```bash
godot --headless --script tests/bench_dead_removal.gd
```
