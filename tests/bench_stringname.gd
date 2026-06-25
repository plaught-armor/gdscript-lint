# gdlint: disable-file
extends SceneTree
## Why StringName over String for identifiers: a StringName is interned, so `==`
## is a pointer/id compare (O(1)) and a dict lookup hashes a cached id — where a
## String compares character-by-character (O(len)) and re-hashes. This measures
## both on the build, plus the one-time cost you pay to intern a String.
##
## Best-of-REPS, accumulated into a sink. Run:
##   godot --headless --script tests/bench_stringname.gd

const N: int = 1_000_000
const REPS: int = 7

var _sink: int = 0


func _initialize() -> void:
	print("StringName vs String — best-of-%d, N=%d (us). Lower = faster." % [REPS, N])
	_bench_compare()
	_bench_dict()
	_bench_intern()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_compare() -> void:
	# Equal-but-distinct long identifiers — worst case for String (must walk all chars).
	var sn_a: StringName = &"enemy_perception_alert_state_changed"
	var sn_b: StringName = &"enemy_perception_alert_state_changed"
	var s_a: String = "enemy_perception_alert_state_changed".substr(0) # force a distinct instance
	var s_b: String = "enemy_perception_alert_state_changed".substr(0)
	var best_sn: int = 1 << 60
	var best_s: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			if sn_a == sn_b:
				_sink += 1
		best_sn = _best(best_sn, Time.get_ticks_usec() - t0)
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			if s_a == s_b:
				_sink += 1
		best_s = _best(best_s, Time.get_ticks_usec() - t1)
	print(
		(
				"  ==  StringName=%d  String=%d  → String is %.1fx the cost"
				% [best_sn, best_s, float(best_s) / float(maxi(best_sn, 1))]
		),
	)


func _bench_dict() -> void:
	var sn_key: StringName = &"attack_speed"
	var s_key: String = "attack_speed".substr(0)
	var sn_d: Dictionary = { &"damage": 1, &"attack_speed": 2, &"crit_chance": 3 }
	var s_d: Dictionary = { "damage": 1, "attack_speed": 2, "crit_chance": 3 }
	var best_sn: int = 1 << 60
	var best_s: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			_sink += sn_d[sn_key]
		best_sn = _best(best_sn, Time.get_ticks_usec() - t0)
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			_sink += s_d[s_key]
		best_s = _best(best_s, Time.get_ticks_usec() - t1)
	print(
		(
				"  dict[key]  StringName=%d  String=%d  → String is %.1fx the cost"
				% [best_sn, best_s, float(best_s) / float(maxi(best_sn, 1))]
		),
	)


func _bench_intern() -> void:
	# The cost you DO pay: turning a runtime String into a StringName interns it.
	var src: String = "some_runtime_identifier".substr(0)
	var best: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var sn: StringName = StringName(src)
			_sink += sn.length()
		best = _best(best, Time.get_ticks_usec() - t0)
	print("  intern  StringName(str)=%d us for %d (do this once, at a boundary — not per frame)" % [best, N])
