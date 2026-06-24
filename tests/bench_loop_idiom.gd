# gdlint: disable-file
extends SceneTree
## Measures the loop-idiom rules' perf claims (L1/L2/L3) so they can graduate
## from advisory -> blocking only on real data. Best-of-REPS, surrounding work
## held identical, result accumulated into _sink so nothing optimizes away.
## Run: godot --headless --script tests/gd-lint/bench_loop_idiom.gd

const N: int = 2_000_000
const REPS: int = 7

var _sink: int = 0


func _initialize() -> void:
	_bench_l3()
	_bench_l1()
	_bench_l2()
	quit()


func _best_us(a: int, b: int) -> int:
	return a if a < b else b


func _bench_l3() -> void:
	var best_range: int = 1 << 60
	var best_direct: int = 1 << 60
	for _r: int in REPS:
		var s0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in range(N):
			s0 += i
		best_range = _best_us(best_range, Time.get_ticks_usec() - t0)
		var s1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			s1 += i
		best_direct = _best_us(best_direct, Time.get_ticks_usec() - t1)
		_sink += s0 + s1
	print("L3  range(N)=%d us  for-i:int-in-N=%d us  ratio=%.2fx" % [best_range, best_direct, float(best_range) / float(best_direct)])


func _bench_l1() -> void:
	var arr: PackedInt32Array = []
	arr.resize(N)
	for i: int in N:
		arr[i] = i
	var best_idx: int = 1 << 60
	var best_dir: int = 1 << 60
	for _r: int in REPS:
		var s0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in range(arr.size()):
			s0 += arr[i]
		best_idx = _best_us(best_idx, Time.get_ticks_usec() - t0)
		var s1: int = 0
		var t1: int = Time.get_ticks_usec()
		for v: int in arr:
			s1 += v
		best_dir = _best_us(best_dir, Time.get_ticks_usec() - t1)
		_sink += s0 + s1
	print("L1  range(size)idx=%d us  for-v-in-arr=%d us  ratio=%.2fx" % [best_idx, best_dir, float(best_idx) / float(best_dir)])


func _bench_l2() -> void:
	var best_range: int = 1 << 60
	var best_while: int = 1 << 60
	for _r: int in REPS:
		var s0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in range(N - 1, -1, -1):
			s0 += i
		best_range = _best_us(best_range, Time.get_ticks_usec() - t0)
		var s1: int = 0
		var t1: int = Time.get_ticks_usec()
		var j: int = N - 1
		while j >= 0:
			s1 += j
			j -= 1
		best_while = _best_us(best_while, Time.get_ticks_usec() - t1)
		_sink += s0 + s1
	print("L2  descending-range=%d us  while=%d us  ratio=%.2fx" % [best_range, best_while, float(best_range) / float(best_while)])


func _finalize() -> void:
	print("sink=%d" % _sink)
