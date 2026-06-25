# gdlint: disable-file
extends Node
## Pool demo. Fills the bank (CAP=8), ticks until some expire, then spawns again —
## showing freed slot INDICES get reused (no growth, no alloc). import then --path.

func _ready() -> void:
	var pool: ProjectilePool = ProjectilePool.new()
	print("[demo] CAP=%d, free=%d" % [ProjectilePool.CAP, pool.free_count()])

	# Spawn 5 with staggered lifetimes; note which slot index each got.
	var slots: PackedInt32Array = []
	for i: int in 5:
		slots.append(pool.spawn(Vector2(i, 0), Vector2(1, 0), 1.0 + float(i) * 0.5))
	print("[demo] spawned 5 → slots %s, active=%d free=%d" % [slots, pool.active_count(), pool.free_count()])

	# Tick 1.2s: the two shortest-lived (ttl 1.0, 1.5) expire and return to the pool.
	pool.tick(1.2)
	print("[demo] after 1.2s tick → active=%d free=%d" % [pool.active_count(), pool.free_count()])

	# Spawn 2 more — they REUSE the just-freed slot indices (no new storage).
	var reused: PackedInt32Array = []
	for i: int in 2:
		reused.append(pool.spawn(Vector2(9, 9), Vector2(0, 1), 2.0))
	print("[demo] spawned 2 more → reused slots %s (were freed above)" % reused)
	print("[demo] active=%d free=%d (CAP still %d, no growth)" % [pool.active_count(), pool.free_count(), ProjectilePool.CAP])

	# Drain everything, then prove exhaustion returns -1.
	pool.tick(100.0)
	print("[demo] drained → active=%d free=%d" % [pool.active_count(), pool.free_count()])
	for i: int in ProjectilePool.CAP + 2:
		pool.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
	var overflow: int = pool.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
	print("[demo] over-spawned CAP+ → exhausted spawn returns %d" % overflow)

	get_tree().quit()
