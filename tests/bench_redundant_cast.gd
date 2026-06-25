# gdlint: disable-file
extends SceneTree
## Backs Part II H14 / H14b: a redundant `as T` adds a Variant round-trip.
##  - H14: after `if v is T:` the compiler has narrowed v to T, so `v.field` is
##    already typed; wrapping it as `(v as T).field` re-casts for nothing.
##  - H14b: a typed container (`Dictionary[K, V]`, `Array[T]`) already returns a
##    typed element; `(d[k] as T).field` is the same wasted round-trip.
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
	for rep: int in REPS:
		var a0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			if v is Foo:
				a0 += (v as Foo).x # redundant: already narrowed by `is`
		best_as = _best(best_as, Time.get_ticks_usec() - t0)
		var a1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			if v is Foo:
				a1 += v.x # direct: narrowed access
		best_direct = _best(best_direct, Time.get_ticks_usec() - t1)
		_sink += float(a0 + a1)
	print(
		(
				"H14    (v as Foo).x=%d us  narrowed v.x=%d us  ratio=%.2fx (>1 = redundant cast slower)"
				% [best_as, best_direct, float(best_as) / float(best_direct)]
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
