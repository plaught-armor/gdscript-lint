class_name HitRecord
extends RefCounted
## D1 transient record (RefCounted, no .tres — it exists for one combat
## transaction, then frees) + D3 — the attacker is carried as an integer id, not
## a live Node ref, so a hit that outlives its attacker resolves to null instead
## of dangling into a freed (or recycled) object.

var amount: int = 0
var crit: bool = false
var attacker_id: int = 0


func _init(p_amount: int = 0, p_crit: bool = false, p_attacker_id: int = 0) -> void:
	amount = p_amount
	crit = p_crit
	attacker_id = p_attacker_id
