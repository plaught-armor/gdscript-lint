# gdlint: disable-file
extends SceneTree
## Backs Part II H14 / H14b: what an inline `as T` actually costs.
##  - H14: `is` does NOT narrow — inside `if v is T:` the analyzer still reports
##    v as Variant (autocomplete narrows, the type checker does not). So the four
##    forms measured here are: the per-use cast, the bare dynamic access, a typed
##    local bound once above the loop, and that same bind repeated per iteration.
##    Only the bind is statically typed, and hoisted it is also the fastest.
##  - H14b: a typed container (`Dictionary[K, V]`, `Array[T]`) DOES return a
##    statically typed element; `(d[k] as T).field` there is a wasted round-trip.
## Best-of-REPS, summed into _sink. Run: godot --headless --script tests/bench_redundant_cast.gd

const N: int = 2_000_000
const REPS: int = 7

var _sink: float = 0.0


class Foo:
	extends RefCounted
	var x: int = 3


func _initialize() -> void:
	_h14_is_then_as()
	_h14b_typed_container()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _h14_is_then_as() -> void:
	var v: Variant = Foo.new()
	var best_as: int = 1 << 60
	var best_direct: int = 1 << 60
	var best_bind_loop: int = 1 << 60
	var best_bind_hoisted: int = 1 << 60
	for rep: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			if v is Foo:
				a0 += (v as Foo).x # per-use cast: pays the check every access
		best_as = _best(best_as, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			if v is Foo:
				a1 += v.x # bare: dynamic Variant access, `is` narrowed nothing
		best_direct = _best(best_direct, Time.get_ticks_usec() - t1)
		var a2: int = 0
		var t2: int = Time.get_ticks_usec()
		for i: int in N:
			if v is Foo:
				var f: Foo = v # bind per iteration: same check as the cast
				a2 += f.x
		best_bind_loop = _best(best_bind_loop, Time.get_ticks_usec() - t2)
		var a3: int = 0
		var t3: int = Time.get_ticks_usec()
		if v is Foo:
			var f_hoisted: Foo = v # bind once: one check, typed accesses after
			for i: int in N:
				a3 += f_hoisted.x
		best_bind_hoisted = _best(best_bind_hoisted, Time.get_ticks_usec() - t3)
		_sink += float(a0 + a1 + a2 + a3)
	print(
		(
				"H14    (v as Foo).x=%d us  bare v.x=%d us  bind-in-loop=%d us  bind-hoisted=%d us  (lower is better; bind-hoisted is also the only statically typed form)"
				% [best_as, best_direct, best_bind_loop, best_bind_hoisted]
		),
	)


func _h14b_typed_container() -> void:
	var d: Dictionary[int, Foo] = { 0: Foo.new() }
	var best_as: int = 1 << 60
	var best_direct: int = 1 << 60
	for rep: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			a0 += (d[0] as Foo).x # redundant: typed container already returns Foo
		best_as = _best(best_as, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			a1 += d[0].x # direct: typed access
		best_direct = _best(best_direct, Time.get_ticks_usec() - t1)
		_sink += float(a0 + a1)
	print(
		(
				"H14b   (d[0] as Foo).x=%d us  typed d[0].x=%d us  ratio=%.2fx (>1 = redundant cast slower)"
				% [best_as, best_direct, float(best_as) / float(best_direct)]
		),
	)
