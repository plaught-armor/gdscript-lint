class_name CombatSystem
extends RefCounted
## D6 — behavior is a pure static transform, NOT a method on the data. resolve()
## takes the manager + a target slot + a HitRecord, mutates the target's hot
## health through the manager's API, and returns whether the hit was lethal. No
## instance state; never construct a CombatSystem.
## D7 — the armor damage multiplier is a table lookup, not an if/elif chain. A new
## armor class is a new row, not new code.
## C2a — NOT a `const` Dictionary (const collections are shared-mutable refs, the
## C1/C2 bug family). Same shape as EnemyRegistry.defs: a `static var` locked
## read-only in _static_init. Key type is int because the enum stores as int.

static var armor_mult: Dictionary[int, float] = {
	EnemyDef.Armor.NONE: 1.0,
	EnemyDef.Armor.LIGHT: 0.7,
	EnemyDef.Armor.HEAVY: 0.4,
}


static func _static_init() -> void:
	if not armor_mult.is_read_only():
		armor_mult.make_read_only()


static func resolve(mgr: EnemyManager, slot: int, hit: HitRecord) -> bool:
	var armor: EnemyDef.Armor = mgr.def_at(slot).armor
	var mult: float = armor_mult[armor]
	var crit_mult: float = 2.0 if hit.crit else 1.0
	var dealt: int = int(roundf(hit.amount * mult * crit_mult))
	mgr.apply_damage(slot, dealt)
	return mgr.health_at(slot) <= 0
