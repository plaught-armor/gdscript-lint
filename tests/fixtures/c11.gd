extends Node

var items: Array = []


func bad() -> void:
	# Non-strict comparator: returns true on equal → breaks strict-weak-ordering.
	# Single-expr comparators; the C11 correctness bug is the only finding.
	items.sort_custom(func(a, b): return a.hp <= b.hp) # EXPECT C11
	items.sort_custom(func(a, b): return a.x >= b.x) # EXPECT C11


func ok() -> void:
	# Strict '<' comparator — correct, no finding.
	items.sort_custom(func(a, b): return a.hp < b.hp)
	# Named comparator: body not visible to a line linter (reviewer's job).
	items.sort_custom(_by_hp)
	# A '<=' outside any sort_custom must not trip C11.
	var clamped: bool = items.size() <= 10
	print(clamped)


func _by_hp(a, b) -> bool:
	return a.hp < b.hp
