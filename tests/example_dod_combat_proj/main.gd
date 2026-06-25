# gdlint: disable-file
extends Node
## Sim driver. Spawns a wave, ticks it as one batch (D8), resolves attacks by id
## (D3) through the pure CombatSystem transform (D6), kills the lethal ones via
## swap-back (P6), and prints the surviving roster. The point: the manager owns
## the data, the system transforms it, ids cross the boundary — no fat Enemy
## object anywhere. Runs as the main scene; import the project once, then:
##   godot --headless --path tests/example_dod_combat_proj

func _ready() -> void:
	var mgr: EnemyManager = EnemyManager.new()

	var ids: Array[int] = []
	ids.append(mgr.spawn(EnemyRegistry.Kind.GRUNT, 10.0))
	ids.append(mgr.spawn(EnemyRegistry.Kind.BRUTE, 12.0))
	ids.append(mgr.spawn(EnemyRegistry.Kind.SKIRMISHER, 8.0))
	ids.append(mgr.spawn(EnemyRegistry.Kind.GRUNT, 9.0))
	print("[demo] spawned %d enemies (one batch, no per-node _process)" % mgr.count())

	# D8 — three batched ticks; every enemy advances toward x=0 at its kind speed.
	for step: int in 3:
		mgr.tick(0.5)
	print("[demo] after 3 ticks, grunt#1 x=%.2f (started 10.0, speed 1.0)" % mgr.pos_at(0))

	# Same 8-dmg crit to each, resolved by id. Armor mult (D7) makes the brute eat
	# far less than the grunts; the skirmisher dies.
	for id: int in ids:
		var slot: int = mgr.slot_of(id)
		if slot < 0:
			continue
		var hit: HitRecord = HitRecord.new(8, true, 0)
		var lethal: bool = CombatSystem.resolve(mgr, slot, hit)
		var kn: StringName = mgr.def_at(slot).kind_name
		var tag: String = " — LETHAL, swap-back removed" if lethal else ""
		print("[demo] hit id=%d (%s): hp now %d%s" % [id, kn, mgr.health_at(slot), tag])
		if lethal:
			mgr.kill(slot)

	print("[demo] survivors: %d" % mgr.count())

	# D3 — ids still resolve correctly after the swap-back reshuffled slots.
	for id: int in ids:
		var slot: int = mgr.slot_of(id)
		var where: String = "dead" if slot < 0 else "alive @slot %d" % slot
		print("[demo]   id=%d -> %s" % [id, where])

	get_tree().quit()
