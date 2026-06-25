# gdlint: disable-file
extends SceneTree
## Backs Part IV D7a: mapping a closed enum to a string key (a file basename, an
## asset name) via `Id.keys()[id].to_lower()` allocates on every call — keys()
## builds a fresh PackedStringArray and to_lower() builds a fresh String. An
## explicit if/elif helper that returns a string *literal* allocates nothing
## (literals are interned), and lets a slot whose asset name diverges from the
## enum spelling be overridden in one place.
##
## Best-of-REPS, accumulated into _sink.
##
## Run: godot --headless --script tests/bench_convention_dispatch.gd

const N: int = 1_000_000
const REPS: int = 7

var _sink: float = 0.0

enum Id { POTION, SWORD_GRIP, SHIELD, HELMET, BOOTS, RING }


func _initialize() -> void:
	_bench_keys_vs_helper()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _basename(id: int) -> String:
	if id == Id.POTION:
		return "potion"
	if id == Id.SWORD_GRIP:
		return "sword_grip"
	if id == Id.SHIELD:
		return "shield"
	if id == Id.HELMET:
		return "helmet"
	if id == Id.BOOTS:
		return "boots"
	if id == Id.RING:
		return "ring"
	return ""


func _bench_keys_vs_helper() -> void:
	var best_keys: int = 1 << 60
	var best_help: int = 1 << 60
	for rep: int in REPS:
		# --- keys()[id].to_lower(): allocates a PackedStringArray + a String/call ---
		var c0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var s: String = Id.keys()[i % 6].to_lower()
			c0 += s.length()
		best_keys = _best(best_keys, Time.get_ticks_usec() - t0)
		# --- explicit helper returning interned literals: no alloc ---
		var c1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			var s2: String = _basename(i % 6)
			c1 += s2.length()
		best_help = _best(best_help, Time.get_ticks_usec() - t1)
		_sink += float(c0 + c1)
	print(
		(
				"D7a  keys()[id].to_lower()=%d us  if/elif helper=%d us  ratio=%.2fx"
				% [best_keys, best_help, float(best_keys) / float(best_help)]
		),
	)
