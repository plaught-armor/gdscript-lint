# gdlint: disable-file
extends SceneTree
## Backs P9 (#68834, "Lua-style dict access is slower", fixed 4.4): compares
## `d.key` (Lua-style dot access) against `d["key"]` (bracket) on a Dictionary.
## The historical ~2x penalty for dot access should be gone on 4.8.dev — this
## measures whether it is. Best-of-REPS, summed into _sink.
## Run: godot --headless --script tests/bench_dict_access.gd

const N: int = 2_000_000
const REPS: int = 7

var _sink: float = 0.0


func _initialize() -> void:
	_bench_dot_vs_bracket()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_dot_vs_bracket() -> void:
	var d: Dictionary = { "value": 7 }
	var best_dot: int = 1 << 60
	var best_brk: int = 1 << 60
	for rep: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			a0 += d.value
		best_dot = _best(best_dot, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			a1 += d["value"]
		best_brk = _best(best_brk, Time.get_ticks_usec() - t1)
		_sink += float(a0 + a1)
	print(
		(
				"P9   d.value(Lua)=%d us  d[\"value\"](bracket)=%d us  ratio=%.2fx (want ~1.0 = gap closed)"
				% [best_dot, best_brk, float(best_dot) / float(best_brk)]
		),
	)
