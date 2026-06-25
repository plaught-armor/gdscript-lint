class_name EnemyDef
extends Resource
## D1 + D5 — the COLD half of an enemy: the per-*kind* constants that never
## change at runtime (max health, speed, contact damage, armor class). One
## EnemyDef is shared by every runtime instance of that kind; the hot per-frame
## state (current hp, position) lives in EnemyManager's parallel arrays, NOT here.
## Pure data: fields + _init, no behavior (behavior is in CombatSystem, D6).

enum Armor { NONE, LIGHT, HEAVY }

@export var kind_name: StringName = &""
@export var max_health: int = 10
@export var speed: float = 1.0
@export var contact_damage: int = 1
@export var armor: Armor = Armor.NONE


func _init(
		p_kind: StringName = &"",
		p_max_health: int = 10,
		p_speed: float = 1.0,
		p_contact_damage: int = 1,
		p_armor: Armor = Armor.NONE,
) -> void:
	kind_name = p_kind
	max_health = p_max_health
	speed = p_speed
	contact_damage = p_contact_damage
	armor = p_armor
