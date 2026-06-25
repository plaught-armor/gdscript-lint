# gdlint: disable-file
extends SceneTree
## Empirically tests the standalone (no-frame-loop) typing/iteration traps from
## Part II. Each prints what it observed + a verdict.
## Run: godot --headless --script tests/repro_typing_traps.gd

enum Hue { RED, GREEN, BLUE }

var _member_v: int = 0


func _initialize() -> void:
	_h3_enum_is_int()
	_h6_lambda_capture()
	_h7_float_to_int()
	_m4_mutate_during_iter()
	_h11_json_typed_dict()
	quit()


func _h3_enum_is_int() -> void:
	var e: Hue = Hue.GREEN
	var is_int: bool = typeof(e) == TYPE_INT
	print("H3     %-14s | typeof(Hue.GREEN)==TYPE_INT -> %s (enum is int at runtime)" % ["CONFIRMED" if is_int else "CHANGED", str(is_int)])


func _h6_lambda_capture() -> void:
	var local_v: int = 0
	var f: Callable = func() -> void:
		local_v += 1 # captured by value (a snapshot)
		_member_v += 1 # member via self -> by reference
	f.call()
	# #69014: after the call, the local is unchanged (the lambda mutated its copy)
	# while the member did change.
	var by_value: bool = local_v == 0
	var by_ref: bool = _member_v == 1
	print("H6     %-14s | after lambda: local=%d (want 0=by-value), member=%d (want 1=by-ref)" % ["CONFIRMED" if (by_value and by_ref) else "CHANGED", local_v, _member_v])


func _h7_float_to_int() -> void:
	var f: float = 2.9
	var arr: Array = []
	arr.resize(f) # float arg to an int param — silently truncates?
	var truncated: bool = arr.size() == 2
	print("H7     %-14s | Array.resize(2.9) -> size=%d (want 2 = silent truncation)" % ["CONFIRMED" if truncated else "CHANGED", arr.size()])


func _m4_mutate_during_iter() -> void:
	var arr: Array = [1, 2, 3, 4, 5, 6]
	var seen: Array = []
	for x: int in arr:
		seen.append(x)
		if x == 2:
			arr.erase(3) # mutate the container mid-iteration
	# If iteration skips, seen will be missing an element vs the original 6.
	var skipped: bool = seen.size() != 6 or not (3 in seen)
	print("M4     %-14s | erase during for-iter -> visited %s (skips if 3 missing / size<6)" % ["LIVE" if skipped else "no-skip-here", str(seen)])


func _h11_json_typed_dict() -> void:
	var raw: Variant = JSON.parse_string('{"a": "not-an-int", "b": 2}')
	var enforced: String = "n/a"
	if raw is Dictionary:
		# Assign untyped JSON into a typed Dictionary[String, int]. Does it reject
		# the string value, or silently accept the wrong shape?
		var typed: Dictionary[String, int] = { }
		var accepted_wrong: bool = false
		typed.assign(raw)
		# If we get here without error, the wrong-typed value was accepted.
		accepted_wrong = typed.has("a")
		enforced = "NOT-enforced (wrong value accepted)" if accepted_wrong else "enforced/rejected"
	print("H11    %-14s | typed Dict from JSON with a string value -> %s" % ["see", enforced])
