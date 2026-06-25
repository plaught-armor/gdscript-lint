# gdlint: disable-file
class_name EnemyRegistry
extends RefCounted
## Second registry — exists to test that _static_init order is deterministic and
## follows the order RegistryRoot references them in (Item then Enemy).

enum Id { NONE, GRUNT, BRUTE }

static var all_defs: Array[SIItemDef] = [null, SIItemDef.new("grunt"), SIItemDef.new("brute")]


static func _static_init() -> void:
	print("  [static_init] EnemyRegistry RUNS")
	if not all_defs.is_read_only():
		all_defs.make_read_only()
