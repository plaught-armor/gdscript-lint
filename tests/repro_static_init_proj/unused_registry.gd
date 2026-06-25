# gdlint: disable-file
class_name UnusedRegistry
extends RefCounted
## Declared with class_name but NEVER referenced by any code. The crux test for
## "lazy vs eager": if its [static_init] line appears in the boot trace, then
## _static_init runs eagerly at script/class load for every class_name'd class —
## refuting the bible's "runs the first time the class is referenced". If it is
## absent, the claim holds (lazy on first reference).

enum Id { NONE, GHOST }

static var all_defs: Array[SIItemDef] = [null, SIItemDef.new("ghost")]


static func _static_init() -> void:
	print("  [static_init] UnusedRegistry RUNS  <-- if you see this, static_init is EAGER")
