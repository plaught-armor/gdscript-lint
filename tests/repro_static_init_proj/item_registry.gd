# gdlint: disable-file
class_name ItemRegistry
extends RefCounted
## Registry shape from Part V §4a. `_static_init` is the boot hook under test:
## does it run lazily on first class reference, or eagerly at script load? Does
## it run exactly once? The print markers below answer both when correlated with
## registry_root.gd's reference order.

enum Id { NONE, POTION, SWORD }

# Bible §4a names this `ALL`; the lint gate wants snake_case for a `static var`,
# so the repro uses `all_defs`. Name is irrelevant to the static-init
# timing/order/lock this project measures.

static var all_defs: Array[SIItemDef] = [null, SIItemDef.new("potion"), SIItemDef.new("sword")]


static func _static_init() -> void:
	print("  [static_init] ItemRegistry RUNS")
	_validate()
	if not all_defs.is_read_only():
		all_defs.make_read_only()


static func _validate() -> void:
	for i: int in range(1, all_defs.size()):
		if all_defs[i] == null:
			push_error("[ItemRegistry] all_defs[%d] is null" % i)


static func get_def(id: Id) -> SIItemDef:
	return all_defs[id]
