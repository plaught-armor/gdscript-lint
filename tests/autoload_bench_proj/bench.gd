# gdlint: disable-file
extends Node
## Completes Part III §2's call-overhead ladder with the one path that needs a
## real project: the autoload global identifier (`Bus.method()`). Re-measures
## inline / static / instance here too so the autoload row shares one baseline.
## Runs as the project main scene (autoload globals aren't registered under a
## bare `--script` custom main loop):
##   godot --headless --path tests/autoload_bench_proj

const N: int = 600_000
const REPS: int = 7

var _sink: float = 0.0


class StaticHelper:
	static func add(x: int) -> int:
		return x + 1


class Inst:
	func add(x: int) -> int:
		return x + 1


func _ready() -> void:
	var inl: int = _bench_inline()
	print("  inline expression            = %7d us  %8.1f ns/op  1.00x" % [inl, _ns_per_op(inl)])
	_report("static func on RefCounted", inl, _bench_static())
	_report("instance method, cached ref", inl, _bench_instance())
	_report("autoload global ident Bus.x()", inl, _bench_autoload())
	get_tree().quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _ns_per_op(t: int) -> float:
	# t is the best-of-REPS wall time in us for one N-iteration loop.
	return float(t) * 1000.0 / float(N)


func _report(label: String, base: int, t: int) -> void:
	print("  %-28s = %7d us  %8.1f ns/op  %.2fx" % [label, t, _ns_per_op(t), float(t) / float(base)])


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
			acc += StaticHelper.add(i)
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


func _bench_autoload() -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += Bus.add(i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best
