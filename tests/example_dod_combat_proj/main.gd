# gdlint: disable-file
extends Node
## Combat demo. Batched tick (D8) + armor table (D7), and the TWO ways dead leave
## a manager-owned list (bible/removing-dead-entities.md):
##   kill(slot) — swap-back, O(1), for a SINGLE known removal (phase 1)
##   cull()     — write-cursor compaction, one pass, for a MASS removal (phase 2)
## Import the project once, then: godot --headless --path tests/example_dod_combat_proj

func _ready() -> void:
	var mgr: EnemyManager = EnemyManager.new()
	var ids: PackedInt64Array = []
	ids.append(mgr.spawn(EnemyRegistry.Kind.SKIRMISHER, 8.0)) # id 1, hp 6
	ids.append(mgr.spawn(EnemyRegistry.Kind.GRUNT, 10.0)) # id 2, hp 10
	ids.append(mgr.spawn(EnemyRegistry.Kind.BRUTE, 12.0)) # id 3, hp 40
	ids.append(mgr.spawn(EnemyRegistry.Kind.GRUNT, 9.0)) # id 4, hp 10
	ids.append(mgr.spawn(EnemyRegistry.Kind.SKIRMISHER, 7.0)) # id 5, hp 6
	ids.append(mgr.spawn(EnemyRegistry.Kind.BRUTE, 11.0)) # id 6, hp 40
	print("[demo] spawned %d enemies" % mgr.count())

	# D8 — one batched pass advances every enemy toward x=0.
	for step: int in 3:
		mgr.tick(0.5)

	# Phase 1 — SINGLE removals: snipe the two skirmishers, each via swap-back kill.
	print("[demo] phase 1 — single swap-back kills:")
	for id: int in [ids[0], ids[4]]:
		var slot: int = mgr.slot_of(id)
		if slot < 0:
			continue
		var lethal: bool = CombatSystem.resolve(mgr, slot, HitRecord.new(8, true, 0))
		print("[demo]   sniped id=%d lethal=%s" % [id, lethal])
		if lethal:
			mgr.kill(slot)
	print("[demo]   survivors: %d" % mgr.count())

	# Phase 2 — MASS removal: a flat AoE blasts everyone; the newly dead are
	# compacted out in ONE write-cursor pass (not N swap-backs), survivors keep
	# their relative order.
	print("[demo] phase 2 — AoE then one cull() compaction:")
	for id: int in ids:
		var slot: int = mgr.slot_of(id)
		if slot >= 0:
			mgr.apply_damage(slot, 12) # flat 12 — kills grunts (hp 10), not brutes (hp 40)
	var before: int = mgr.count()
	var removed: int = mgr.cull()
	print("[demo]   AoE 12; cull() removed %d in one pass, %d -> %d" % [removed, before, mgr.count()])

	# D3 — ids still resolve after compaction; survivors kept relative order.
	for id: int in ids:
		var slot: int = mgr.slot_of(id)
		print("[demo]   id=%d -> %s" % [id, "dead" if slot < 0 else "alive @slot %d" % slot])
	get_tree().quit()
