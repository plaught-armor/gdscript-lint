class_name WeaponPartDef
extends Resource
## A POD upgrade delta (D1). The modifier ORDER is the design lever: flat adds
## first, then `increased` (additive %) sum, then `more` (multiplicative %)
## multiply — the Path-of-Exile pipeline. Designers author these as .tres so the
## deltas are diffable; UpgradeSystem.apply_part folds one into a base WeaponDef.

@export var flat_damage: float = 0.0
@export var increased_damage: float = 0.0 # additive %, 0.5 = +50%
@export var more_damage: float = 0.0 # multiplicative %, 0.2 = x1.2
@export var flat_attack_speed: float = 0.0
