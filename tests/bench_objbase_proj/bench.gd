# gdlint: disable-file
extends SceneTree
## Does the base class of a never-instantiated `class_name`'d helper move the cost
## of calling its `static func`? Needs a real project because `class_name` globals
## resolve from project.godot, not from a bare --script run.
## Backs the D9 note that base-class choice is perf-neutral for static-only systems.
##
## Run: godot --headless --path tests/bench_objbase_proj --script bench.gd

const N: int = 1_000_000
const REPS: int = 7

var _sink: int = 0


func best(c: Callable) -> float:
	var b: float = INF
	for r in REPS:
		var t0: int = Time.get_ticks_usec()
		c.call()
		b = minf(b, float(Time.get_ticks_usec() - t0) * 1000.0 / float(N))
	return b


func _init() -> void:
	print("static func dispatch, ns/op (best-of-%d, N=%d)" % [REPS, N])
	print("  class_name ... extends Object     : %.1f" % best(func() -> void:
		for i in N: _sink += ObjUtil.add(i, 1)))
	print("  class_name ... extends RefCounted : %.1f" % best(func() -> void:
		for i in N: _sink += RefUtil.add(i, 1)))
	print("  sink=%d" % _sink)
	quit()
