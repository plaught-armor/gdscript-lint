# gdlint: disable-file
extends SceneTree
## Backs Part III §1 (dispatch mechanism) and §2 (call overhead & indirection).
## Best-of-REPS, all surrounding work held identical, results accumulated into
## _sink so nothing is dead-code-eliminated. Discriminators are read from a
## pre-filled PackedInt32Array (outside timing) so every dispatch variant pays the
## same key-fetch cost and the compiler can't constant-fold the matched arm.
##
## §1 baseline = Array[Callable] index (reported ratio = T_callable / T_x; >1 faster).
## §2 baseline = hand-inlined expression (reported ratio = T_x / T_inline; >1 slower).
##
## Run: godot --headless --script tests/bench_dispatch_mechanism.gd

const N: int = 600_000
const REPS: int = 7

var _sink: float = 0.0
var _keys3: PackedInt32Array = []
var _keys6: PackedInt32Array = []


# --- 3-arm dispatch targets ---
func _a0(x: int) -> int:
	return x + 1


func _a1(x: int) -> int:
	return x + 2


func _a2(x: int) -> int:
	return x + 3


# --- 6-arm dispatch targets ---
func _b0(x: int) -> int:
	return x + 1


func _b1(x: int) -> int:
	return x + 2


func _b2(x: int) -> int:
	return x + 3


func _b3(x: int) -> int:
	return x + 4


func _b4(x: int) -> int:
	return x + 5


func _b5(x: int) -> int:
	return x + 6


class Helper:
	static func add(x: int) -> int:
		return x + 1


class Inst:
	func add(x: int) -> int:
		return x + 1


class TargetNode extends Node:
	func add(x: int) -> int:
		return x + 1


class Emitter extends Node:
	signal pinged(x: int)


class Listener extends Node:
	var acc: int = 0


	func on_ping(x: int) -> void:
		acc += x


func _initialize() -> void:
	_keys3.resize(N)
	_keys6.resize(N)
	for i: int in N:
		_keys3[i] = i % 3
		_keys6[i] = 5 # always the last of 6 arms — isolates linear-scan cost
	print("--- §1 dispatch (baseline = Array[Callable] index = 1.00x; >1 faster) ---")
	var base: int = _bench_callable()
	print("  Array[Callable] index        = %7d us  1.00x" % base)
	_report1("match + direct call", base, _bench_match3_call())
	_report1("if/elif + direct call", base, _bench_ifelif3_call())
	_report1("if/elif + inline body", base, _bench_ifelif3_inline())
	_report1("match, 6 arms, hit last", base, _bench_match6_last())
	_report1("if/elif, 6 arms, hit last", base, _bench_ifelif6_last())
	print("--- §2 call overhead (baseline = inline = 1.00x; >1 slower) ---")
	var inl: int = _bench_inline()
	print("  inline expression            = %7d us  1.00x" % inl)
	_report2("static func on RefCounted", inl, _bench_static())
	_report2("instance method, cached ref", inl, _bench_instance())
	_report2("get_node() per call", inl, _bench_get_node())
	_report2("signal.emit(), 1 listener", inl, _bench_signal(1))
	_report2("signal.emit(), 4 listeners", inl, _bench_signal(4))
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _report1(label: String, base: int, t: int) -> void:
	print("  %-28s = %7d us  %.2fx" % [label, t, float(base) / float(t)])


func _report2(label: String, base: int, t: int) -> void:
	print("  %-28s = %7d us  %.2fx" % [label, t, float(t) / float(base)])

# ---------------- §1 dispatch ----------------


func _bench_callable() -> int:
	var tbl: Array[Callable] = [_a0, _a1, _a2]
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += tbl[_keys3[i]].call(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_match3_call() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			match _keys3[i]:
				0:
					acc += _a0(i)
				1:
					acc += _a1(i)
				_:
					acc += _a2(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_ifelif3_call() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var k: int = _keys3[i]
			if k == 0:
				acc += _a0(i)
			elif k == 1:
				acc += _a1(i)
			else:
				acc += _a2(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_ifelif3_inline() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var k: int = _keys3[i]
			if k == 0:
				acc += i + 1
			elif k == 1:
				acc += i + 2
			else:
				acc += i + 3
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_match6_last() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			match _keys6[i]:
				0:
					acc += _b0(i)
				1:
					acc += _b1(i)
				2:
					acc += _b2(i)
				3:
					acc += _b3(i)
				4:
					acc += _b4(i)
				_:
					acc += _b5(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_ifelif6_last() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var k: int = _keys6[i]
			if k == 0:
				acc += _b0(i)
			elif k == 1:
				acc += _b1(i)
			elif k == 2:
				acc += _b2(i)
			elif k == 3:
				acc += _b3(i)
			elif k == 4:
				acc += _b4(i)
			else:
				acc += _b5(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best

# ---------------- §2 call overhead ----------------


func _bench_inline() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += i + 1
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_static() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += Helper.add(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_instance() -> int:
	var inst: Inst = Inst.new()
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += inst.add(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_get_node() -> int:
	var target: TargetNode = TargetNode.new()
	target.name = "Target"
	get_root().add_child(target)
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += (get_root().get_node(^"Target") as TargetNode).add(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	target.queue_free()
	return best


func _bench_signal(listeners: int) -> int:
	# Measures emit dispatch + delivery to every listener (each does acc += x) —
	# i.e. the real cost of using a signal, not the bare emit in isolation.
	var emitter: Emitter = Emitter.new()
	get_root().add_child(emitter)
	var nodes: Array[Listener] = []
	for n: int in listeners:
		var l: Listener = Listener.new()
		get_root().add_child(l)
		emitter.pinged.connect(l.on_ping)
		nodes.append(l)
	var best: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			emitter.pinged.emit(i)
		best = _best(best, Time.get_ticks_usec() - t0)
	for l: Listener in nodes:
		_sink += float(l.acc)
		l.queue_free()
	emitter.queue_free()
	return best
