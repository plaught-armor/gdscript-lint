class_name UpgradeSystem
extends RefCounted
## D6 pure transform — folds a part into a base, producing a NEW computed WeaponDef.
## The order of operations IS the system: flat-add first, then the additive `%`
## (increased) bucket, then the multiplicative `%` (more) bucket. Same modifiers in
## a different order give different numbers (100% increased + 100% more on base 10
## = 10x1.5x1.2 ... order-as-set keeps the result independent of equip order).

static func apply_part(base: WeaponDef, part: WeaponPartDef) -> WeaponDef:
	var out: WeaponDef = WeaponDef.new()
	out.damage = (
			(base.damage + part.flat_damage) * (1.0 + part.increased_damage) * (1.0 + part.more_damage)
	)
	out.attack_speed = base.attack_speed + part.flat_attack_speed
	out.crit_chance = base.crit_chance
	return out
