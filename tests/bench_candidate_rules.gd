# gdlint: disable-file
extends SceneTree
## Measures the perf claim behind each candidate linter rule before we decide to
## add it. Best-of-REPS, work accumulated into _sink. C9 (method collision) is
## correctness-only, no perf claim, not benched.
## Run: godot --headless --script tests/gd-lint/bench_candidate_rules.gd

const N: int = 2_000_000
const REPS: int = 5
const PRINTS: int = 10_000

var _sink: float = 0.0


class Dispatchee:
	func foo(x: int) -> int:
		return x + 1


func _initialize() -> void:
	_bench_p22()
	_bench_h13()
	_bench_c3_c14()
	_bench_s11()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_p22() -> void:
	var fv: float = 0.37
	var best_un: int = 1 << 60
	var best_ty: int = 1 << 60
	for _r: int in REPS:
		var a0: float = 0.0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			a0 += clamp(fv, 0.0, 1.0) + abs(fv) + max(fv, 0.5)
		best_un = _best(best_un, Time.get_ticks_usec() - t0)
		var a1: float = 0.0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			a1 += clampf(fv, 0.0, 1.0) + absf(fv) + maxf(fv, 0.5)
		best_ty = _best(best_ty, Time.get_ticks_usec() - t1)
		_sink += a0 + a1
	print("P22  clamp/abs/max(untyped)=%d us  clampf/absf/maxf=%d us  ratio=%.2fx" % [best_un, best_ty, float(best_un) / float(best_ty)])


func _bench_h13() -> void:
	var d: Dispatchee = Dispatchee.new()
	var best_call: int = 1 << 60
	var best_direct: int = 1 << 60
	for _r: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			a0 += int(d.call(&"foo", i))
		best_call = _best(best_call, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			a1 += d.foo(i)
		best_direct = _best(best_direct, Time.get_ticks_usec() - t1)
		_sink += float(a0 + a1)
	print("H13  call(&\"foo\")=%d us  direct d.foo()=%d us  ratio=%.2fx" % [best_call, best_direct, float(best_call) / float(best_direct)])


func _bench_c3_c14() -> void:
	var src: Array[int] = []
	src.resize(N)
	for i: int in N:
		src[i] = i
	var untyped: Array = src
	var typed: Array[int] = src
	var best_un: int = 1 << 60
	var best_ty: int = 1 << 60
	for _r: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for x in untyped:
			a0 += x
		best_un = _best(best_un, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for x: int in typed:
			a1 += x
		best_ty = _best(best_ty, Time.get_ticks_usec() - t1)
		_sink += float(a0 + a1)
	print("C3/C14  iterate-untyped-Array=%d us  iterate-typed-Array[int]=%d us  ratio=%.2fx" % [best_un, best_ty, float(best_un) / float(best_ty)])


func _bench_s11() -> void:
	var t0: int = Time.get_ticks_usec()
	for i: int in PRINTS:
		print("log line ", i)
	var dt: int = Time.get_ticks_usec() - t0
	print("S11  %d print() calls = %d us  -> %.2f us/call" % [PRINTS, dt, float(dt) / float(PRINTS)])
