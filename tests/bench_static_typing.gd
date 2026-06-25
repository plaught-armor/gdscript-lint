# gdlint: disable-file
extends SceneTree
## Backs the headline claim in Part III §5 / Part II (H1, H2): statically typed
## GDScript runs meaningfully faster than untyped (Variant-dispatched) code,
## because the compiler emits type-specialised instructions instead of boxing
## every value into a Variant and dispatching on its runtime type.
##
## Two pairs, each identical work, untyped vs typed:
##   A) loop var + locals + accumulator all untyped (Variant) vs all typed
##   B) `:=` inferred-typed vs `var x: T =` explicit — should be a WASH (both typed)
## Best-of-REPS, accumulated into _sink.
##
## Run: godot --headless --script tests/bench_static_typing.gd

const N: int = 2_000_000
const REPS: int = 7

var _sink: float = 0.0


func _initialize() -> void:
	_bench_typed_vs_untyped()
	_bench_infer_vs_explicit()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_typed_vs_untyped() -> void:
	var best_un: int = 1 << 60
	var best_ty: int = 1 << 60
	for rep: int in REPS:
		# --- untyped: every value is a Variant ---
		var acc_u = 0
		var t0: int = Time.get_ticks_usec()
		for i in N:
			var a = i * 3
			var b = a - i
			acc_u += b % 7
		best_un = _best(best_un, Time.get_ticks_usec() - t0)
		# --- typed: compiler emits int-specialised ops ---
		var acc_t: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			var a2: int = i * 3
			var b2: int = a2 - i
			acc_t += b2 % 7
		best_ty = _best(best_ty, Time.get_ticks_usec() - t1)
		_sink += float(acc_u + acc_t)
	var pct: float = (1.0 - float(best_ty) / float(best_un)) * 100.0
	print(
		(
				"H1/H2  untyped(Variant)=%d us  typed=%d us  ratio=%.2fx  (typed %.0f%% faster)"
				% [best_un, best_ty, float(best_un) / float(best_ty), pct]
		),
	)


func _bench_infer_vs_explicit() -> void:
	var best_inf: int = 1 << 60
	var best_exp: int = 1 << 60
	for rep: int in REPS:
		# --- `:=` inferred type ---
		var acc_i := 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var a := i * 3
			acc_i += a % 7
		best_inf = _best(best_inf, Time.get_ticks_usec() - t0)
		# --- explicit `var x: T =` ---
		var acc_e: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			var a2: int = i * 3
			acc_e += a2 % 7
		best_exp = _best(best_exp, Time.get_ticks_usec() - t1)
		_sink += float(acc_i + acc_e)
	print(
		(
				"H1b  inferred(:=)=%d us  explicit(: T)=%d us  ratio=%.2fx  (both typed → ~wash)"
				% [best_inf, best_exp, float(best_inf) / float(best_exp)]
		),
	)
