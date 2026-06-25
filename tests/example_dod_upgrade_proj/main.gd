# gdlint: disable-file
extends Node
## Stat-upgrade demo + the AUTHORING-EQUIVALENCE test. apply_part(base, grip) must
## equal the hand-authored sword_mk2.tres, field for field. In production this is a
## GUT invariant; here it runs inline. A designer bumping mk2.tres OR the grip part
## without the other fails it — drift caught loud. import then --path.

# The field set is StringName (interned, typo-safe, the right type for Object.get).
const FIELDS: Array[StringName] = [&"damage", &"attack_speed", &"crit_chance"]


func _ready() -> void:
	var base: WeaponDef = preload("res://base_sword.tres")
	var grip: WeaponPartDef = preload("res://grip_part.tres")
	var authored: WeaponDef = preload("res://sword_mk2.tres")
	var computed: WeaponDef = UpgradeSystem.apply_part(base, grip)

	print("[demo] base: dmg=%.2f spd=%.2f" % [base.damage, base.attack_speed])
	print(
		(
				"[demo] computed apply_part(base, grip): dmg=%.2f spd=%.2f crit=%.2f"
				% [computed.damage, computed.attack_speed, computed.crit_chance]
		),
	)
	print(
		(
				"[demo] authored sword_mk2.tres:         dmg=%.2f spd=%.2f crit=%.2f"
				% [authored.damage, authored.attack_speed, authored.crit_chance]
		),
	)

	var drift: bool = false
	for f: StringName in FIELDS:
		if absf(computed.get(f) - authored.get(f)) > 0.0001: # get(StringName) — P12a
			print("[demo]   DRIFT on %s: computed=%.4f authored=%.4f" % [f, computed.get(f), authored.get(f)])
			drift = true
	print("[demo] authoring-equivalence: %s" % ("DRIFT — fails loud" if drift else "PASS (generator == authored)"))

	get_tree().quit()
