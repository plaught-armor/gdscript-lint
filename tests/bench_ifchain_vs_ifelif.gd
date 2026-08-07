# gdlint: disable-file
extends SceneTree
## if/elif chain  vs  bare-if chain WHEN EVERY ARM RETURNS.
##
## Claim under test: in a function where each arm exits via `return`, a bare-`if`
## chain (`if k==X: return ...`) is neutral-to-faster than the equivalent
## `if/elif/else`, because the `elif`'s trailing jump-to-end is dead code once the
## arm returns — the `return` IS the exit. This is the elif->if sweep decision; it
## does NOT touch the match-vs-if lever (~5x, see bench_dispatch_mechanism.gd).
##
## Two callees, two hit profiles:
##   EARLY  = common arm first, key always hits arm 0 (one compare).
##   LATE   = key always hits the last arm (full linear walk, worst case).
## Each arm returns a computed value (`x + N`) rather than a constant, so the arm
## can't be folded away — but the body is deliberately tiny: what's under test is
## the chain's bytecode shape, not the cost of the work inside an arm.
##
## Run: godot --headless --script tests/bench_ifchain_vs_ifelif.gd

const N: int = 1_000_000
const REPS: int = 7

var _sink: float = 0.0
var _keys_early: PackedInt32Array = []
var _keys_late: PackedInt32Array = []


# ---- if/elif/else, each arm returns ----
func _ifelif(k: int, x: int) -> int:
	if k == 0:
		return x + 1
	elif k == 1:
		return x + 2
	elif k == 2:
		return x + 3
	elif k == 3:
		return x + 4
	elif k == 4:
		return x + 5
	else:
		return x + 6


# ---- bare-if chain, each arm returns (no elif keyword) ----
func _ifchain(k: int, x: int) -> int:
	if k == 0:
		return x + 1
	if k == 1:
		return x + 2
	if k == 2:
		return x + 3
	if k == 3:
		return x + 4
	if k == 4:
		return x + 5
	return x + 6


func _initialize() -> void:
	_keys_early.resize(N)
	_keys_late.resize(N)
	for i: int in N:
		_keys_early[i] = 0 # always arm 0 — one compare either way
		_keys_late[i] = 5 # always last arm — full 5-compare walk
	print("--- if/elif  vs  bare-if chain (every arm returns), best-of-%d, N=%d ---" % [REPS, N])
	print("  DIRECT call (no Callable overhead — isolates chain-shape bytecode):")
	print("  profile        if/elif (us)   bare-if (us)   delta")
	_row("EARLY (hit arm 0)", _bench_elif_direct(_keys_early), _bench_if_direct(_keys_early))
	_row("LATE  (hit arm 5)", _bench_elif_direct(_keys_late), _bench_if_direct(_keys_late))
	print("  Callable .call (dispatch overhead present — sanity cross-check):")
	print("  profile        if/elif (us)   bare-if (us)   delta")
	_row("EARLY (hit arm 0)", _bench(_ifelif, _keys_early), _bench(_ifchain, _keys_early))
	_row("LATE  (hit arm 5)", _bench(_ifelif, _keys_late), _bench(_ifchain, _keys_late))
	print("  (delta = bare-if vs if/elif; negative = bare-if faster)")
	print("  _sink=%f" % _sink)
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _row(label: String, t_elif: int, t_if: int) -> void:
	var pct: float = 100.0 * (float(t_if) - float(t_elif)) / float(t_elif)
	print("  %-18s %8d       %8d       %+.1f%%" % [label, t_elif, t_if, pct])


func _bench(fn: Callable, keys: PackedInt32Array) -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += fn.call(keys[i], i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_elif_direct(keys: PackedInt32Array) -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += _ifelif(keys[i], i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best


func _bench_if_direct(keys: PackedInt32Array) -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var acc: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			acc += _ifchain(keys[i], i)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(acc)
	return best
