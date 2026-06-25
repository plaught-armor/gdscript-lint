# gdlint: disable-file
extends Node
## Perception demo. Six guards stand along a corridor; a player walks past. Each
## tick the manager senses (inline SoA, no per-guard call) and decays the alerted
## set (only the alerted subset is touched). Prints how the alerted set grows as
## the player nears guards and shrinks (2s hold) as they fall out of range.
##   godot --headless --path tests/example_dod_perception_proj  (import first)

func _ready() -> void:
	var gm: GuardManager = GuardManager.new()
	# Guards along X at 2,5,8,11,14,17; mixed view ranges.
	var ids: PackedInt64Array = []
	ids.append(gm.spawn(Vector3(2, 0, 0), 2.0))
	ids.append(gm.spawn(Vector3(5, 0, 0), 3.0))
	ids.append(gm.spawn(Vector3(8, 0, 0), 2.0))
	ids.append(gm.spawn(Vector3(11, 0, 0), 4.0))
	ids.append(gm.spawn(Vector3(14, 0, 0), 2.0))
	ids.append(gm.spawn(Vector3(17, 0, 0), 3.0))
	print("[demo] %d guards; player walks x=0..20" % gm.count())

	var dt: float = 0.5
	for step: int in 21:
		var player: Vector3 = Vector3(float(step), 0, 0)
		gm.sense(player) # alerted set grows where player is in range
		gm.decay(dt) # alerted entries age; expired ones leave the set
		if gm.alerted_count() > 0:
			var who: PackedInt64Array = []
			for id: int in ids:
				if gm.is_alerted(id):
					who.append(id)
			print("[demo] x=%2d  alerted=%d  ids=%s" % [step, gm.alerted_count(), who])

	# Tail: no more sensing — the set drains over the 2s hold (existence-based).
	print("[demo] player gone; draining alerted set:")
	for step: int in 5:
		gm.decay(dt)
		print("[demo]   +%.1fs  alerted=%d" % [(step + 1) * dt, gm.alerted_count()])

	get_tree().quit()
