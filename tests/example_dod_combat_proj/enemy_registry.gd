class_name EnemyRegistry
extends RefCounted
## D1 registry (Part V §4a shape) — the shared EnemyDef table, one row per kind.
## C2a — locked read-only after populate so nothing mutates the shared defs.
## This is the single home of the COLD per-kind data (D5); runtime instances in
## EnemyManager hold only a Kind index into here, never their own copy.

enum Kind { GRUNT, BRUTE, SKIRMISHER }

static var defs: Array[EnemyDef] = [
	EnemyDef.new(&"grunt", 10, 1.0, 2, EnemyDef.Armor.NONE),
	EnemyDef.new(&"brute", 40, 0.5, 6, EnemyDef.Armor.HEAVY),
	EnemyDef.new(&"skirmisher", 6, 2.0, 1, EnemyDef.Armor.LIGHT),
]


static func _static_init() -> void:
	if not defs.is_read_only():
		defs.make_read_only()


static func get_def(kind: Kind) -> EnemyDef:
	return defs[kind]
