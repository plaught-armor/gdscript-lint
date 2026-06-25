# gdlint: disable-file
extends SceneTree
## Backs Part II H4 (typed signal params, #110573) and H10b (type the container
## param, don't take untyped Dictionary/Array and probe).
##  - H4: emit to a handler via a typed-param signal vs an untyped-param signal.
##  - H10b: sum a Dictionary passed as Dictionary[String,int] vs untyped Dictionary.
## Best-of-REPS, summed into _sink. Run: godot --headless --script tests/bench_param_types.gd

const N: int = 1_000_000
const REPS: int = 7
const INNER: int = 8

var _sink: int = 0

signal sig_typed(v: int)
signal sig_untyped(v)


func _on_typed(v: int) -> void:
	_sink += v


func _on_untyped(v) -> void:
	_sink += v


func _initialize() -> void:
	sig_typed.connect(_on_typed)
	sig_untyped.connect(_on_untyped)
	_bench_h4()
	_bench_h10b()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_h4() -> void:
	var best_t: int = 1 << 60
	var best_u: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			sig_typed.emit(i)
		best_t = _best(best_t, Time.get_ticks_usec() - t0)
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			sig_untyped.emit(i)
		best_u = _best(best_u, Time.get_ticks_usec() - t1)
	print("H4   typed-param signal=%d us  untyped-param signal=%d us  ratio=%.2fx (>1 = untyped slower)" % [best_t, best_u, float(best_u) / float(best_t)])


func _sum_typed(d: Dictionary[String, int]) -> int:
	var s: int = 0
	for k: String in d:
		s += d[k]
	return s


func _sum_untyped(d: Dictionary) -> int:
	var s: int = 0
	for k in d:
		s += d[k]
	return s


func _bench_h10b() -> void:
	var td: Dictionary[String, int] = { }
	var ud: Dictionary = { }
	for i: int in INNER:
		td["k%d" % i] = i
		ud["k%d" % i] = i
	var loops: int = N / 4
	var best_t: int = 1 << 60
	var best_u: int = 1 << 60
	for rep: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in loops:
			a0 += _sum_typed(td)
		best_t = _best(best_t, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in loops:
			a1 += _sum_untyped(ud)
		best_u = _best(best_u, Time.get_ticks_usec() - t1)
		_sink += a0 + a1
	print("H10b typed Dict param=%d us  untyped Dict param=%d us  ratio=%.2fx (>1 = untyped slower)" % [best_t, best_u, float(best_u) / float(best_t)])
