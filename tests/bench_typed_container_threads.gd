# gdlint: disable-file
extends SceneTree
## Typed-container assign / `is` test cost, single thread vs N worker threads.
## Tracks godotengine/godot#123791: on builds without it, OPCODE_ASSIGN_TYPED_ARRAY /
## OPCODE_TYPE_TEST_ARRAY (and the DICTIONARY twins) compare the element script via
## Variant::evaluate(OP_EQUAL) -> ObjectDB::get_instance, which takes a global lock.
## Prediction: per-thread cost of those opcodes RISES with thread count (contention)
## instead of staying flat like the `base` control.
##
## Fixed total workload split across T threads (T = 1, 2, 4, 8). Each thread times its
## own slice after a two-phase start barrier (every worker checks in on `_arrived`, then the
## main thread opens `_gate` for all at once); the slowest slice is the wall time. Reported
## number = per-thread ns/op = wall / (TOTAL / T). Flat across T = no contention.
## Best-of-REPS. Run:
##   godot --headless --script tests/bench_typed_container_threads.gd

const TOTAL: int = 4_000_000
const REPS: int = 5
const THREAD_COUNTS: Array[int] = [1, 2, 4, 8]

var _arrived: Semaphore = Semaphore.new()
var _gate: Semaphore = Semaphore.new()


class HelperA extends RefCounted:
	pass


class HelperB extends RefCounted:
	pass


func _initialize() -> void:
	var cases: Array[Array] = [
		["base (int add)", _case_base],
		["assign Array[int]", _case_assign_builtin],
		["assign Array[Node]", _case_assign_native],
		["assign Array[HelperA]", _case_assign_script],
		["assign Dictionary[int, HelperA]", _case_assign_dict_script],
		["is Array[bool] (on Array[int])", _case_is_builtin],
		["is Array[Resource] (on Array[Node])", _case_is_native],
		["is Array[HelperB] (on Array[HelperA])", _case_is_script],
		["element write arr[0] = h (Array[HelperA])", _case_elem_write],
		["element read h = arr[0] (Array[HelperA])", _case_elem_read],
		["element write, untyped Array", _case_elem_write_untyped],
	]
	print(
		"Typed container assign / is, per-thread ns/op — TOTAL=%d, best-of-%d (%s)"
		% [TOTAL, REPS, Engine.get_version_info().string]
	)
	var header: String = "%-40s" % "case"
	for t: int in THREAD_COUNTS:
		header += "%10s" % ("T=%d" % t)
	print(header)
	for c: Array in cases:
		var line: String = "%-40s" % c[0]
		for t: int in THREAD_COUNTS:
			line += "%10.1f" % _run(c[1], t)
		print(line)
	quit()


## Best-of-REPS per-thread ns/op for `fn` split across `threads` threads.
func _run(fn: Callable, threads: int) -> float:
	var slice: int = TOTAL / threads
	var best: int = 1 << 60
	for rep: int in REPS:
		var pool: Array[Thread] = []
		var start_err: Error = OK
		for i: int in threads:
			var th: Thread = Thread.new()
			start_err = th.start(fn.bind(slice))
			if start_err != OK:
				break
			pool.append(th)
		# Barrier: release only once every started worker is parked on _gate, so all
		# slices overlap. Post exactly pool.size() so no permit leaks into a later rep.
		for th: Thread in pool:
			_arrived.wait()
		_gate.post(pool.size())
		var wall: int = 0
		for th: Thread in pool:
			wall = maxi(wall, th.wait_to_finish())
		if start_err != OK:
			push_error("Thread.start failed (%s) at T=%d" % [error_string(start_err), threads])
			return NAN
		best = mini(best, wall)
	return float(best) * 1000.0 / float(slice)


## Worker side of the start barrier: check in, then block until the main thread opens the gate.
func _sync() -> void:
	_arrived.post()
	_gate.wait()


func _case_base(count: int) -> int:
	var sum: int = 0
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		sum += i
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (sum & 0)


func _case_assign_builtin(count: int) -> int:
	var arr: Array[int] = []
	var other: Array[int] = []
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		arr = other
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (arr.size() & 0)


func _case_assign_native(count: int) -> int:
	var arr: Array[Node] = []
	var other: Array[Node] = []
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		arr = other
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (arr.size() & 0)


func _case_assign_script(count: int) -> int:
	var arr: Array[HelperA] = []
	var other: Array[HelperA] = []
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		arr = other
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (arr.size() & 0)


func _case_assign_dict_script(count: int) -> int:
	var d: Dictionary[int, HelperA] = { }
	var other: Dictionary[int, HelperA] = { }
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		d = other
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (d.size() & 0)


func _case_is_builtin(count: int) -> int:
	var hits: int = 0
	var arr: Array = [] as Array[int]
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		if arr is Array[bool]:
			hits += 1
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (hits & 0)


func _case_is_native(count: int) -> int:
	var hits: int = 0
	var arr: Array = [] as Array[Node]
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		if arr is Array[Resource]:
			hits += 1
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (hits & 0)


func _case_is_script(count: int) -> int:
	var hits: int = 0
	var arr: Array = [] as Array[HelperA]
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		if arr is Array[HelperB]:
			hits += 1
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (hits & 0)


func _case_elem_write(count: int) -> int:
	var arr: Array[HelperA] = [HelperA.new()]
	var h: HelperA = HelperA.new()
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		arr[0] = h
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (arr.size() & 0)


func _case_elem_read(count: int) -> int:
	var arr: Array[HelperA] = [HelperA.new()]
	var h: HelperA = null
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		h = arr[0]
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (0 if h == null else 0)


func _case_elem_write_untyped(count: int) -> int:
	var arr: Array = [HelperA.new()]
	var h: HelperA = HelperA.new()
	_sync()
	var t0: int = Time.get_ticks_usec()
	for i: int in count:
		arr[0] = h
	var elapsed: int = Time.get_ticks_usec() - t0
	return elapsed + (arr.size() & 0)
