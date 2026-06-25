# gdlint: disable-file
extends SceneTree
## Backs rule P6: Array.pop_front() / pop_at(0) is O(n) — removing the head shifts
## every remaining element down one slot (#45455). The cost is not the single
## call; it is size x frequency. The worst shape is a DRAIN loop (pop_front until
## empty): each of N removals shifts O(n) elements, so emptying an N-element array
## costs O(n^2). This bench drains the same array four ways and sweeps N so the
## O(n^2) blow-up is visible against the 16_666 us 60fps frame budget — i.e. it
## shows at what N "large" starts to matter.
##
## - pop_front(): O(n^2) drain (the smell).
## - pop_back():  O(n) drain, order reversed (use when order does not matter, or
##                reverse() once up front — reverse is itself O(n)).
## - index cursor: O(n) read forward, no removal at all (the usual right answer —
##                 don't mutate; walk an index).
## - swap-back:   O(1) remove-at-index by overwriting the slot with the LAST
##                element then dropping the tail. Order-agnostic. This is the
##                technique the SwapBackArray addon packages (SwapBackUtil.
##                remove_at_i32 for Packed*, SwapBackArray for Node arrays); the
##                two lines are inlined here so the bench stays dependency-free.
##                NOTE: this arm runs on PackedInt32Array (the addon's value path)
##                while the other three run on Array[int], so the front/swap ratio
##                combines the algorithm delta (O(n^2) vs O(n)) with the container
##                delta (Array vs Packed*). The O(n^2)-vs-O(n) story dominates by
##                orders of magnitude; the container gap is the smaller term.
##
## Best-of-REPS, accumulated into _sink so nothing is optimized away.
##
## Run: /path/to/godot --headless --script tests/bench_pop_front.gd

const SIZES: Array[int] = [100, 1_000, 10_000, 50_000]
const REPS: int = 7
const FRAME_BUDGET_US: int = 16_666

var _sink: int = 0


func _initialize() -> void:
	print("P6 — drain an N-element Array four ways (best-of-%d, us). 60fps frame budget = %d us." % [REPS, FRAME_BUDGET_US])
	print("N\tpop_front\tpop_back\tindex\tswap_back\tfront/swap")
	for n: int in SIZES:
		_bench_one(n)
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _make(n: int) -> Array[int]:
	var a: Array[int] = []
	a.resize(n)
	for i: int in n:
		a[i] = i
	return a


func _make_packed(n: int) -> PackedInt32Array:
	var a: PackedInt32Array = []
	a.resize(n)
	for i: int in n:
		a[i] = i
	return a


func _bench_one(n: int) -> void:
	var best_front: int = 1 << 60
	var best_back: int = 1 << 60
	var best_index: int = 1 << 60
	var best_swap: int = 1 << 60
	for rep: int in REPS:
		# --- drain via pop_front: O(n) shift per removal => O(n^2) total ---
		var af: Array[int] = _make(n)
		var t0: int = Time.get_ticks_usec()
		while not af.is_empty():
			_sink += af.pop_front()
		best_front = _best(best_front, Time.get_ticks_usec() - t0)
		# --- drain via pop_back: O(1) per removal => O(n) total ---
		var ab: Array[int] = _make(n)
		var t1: int = Time.get_ticks_usec()
		while not ab.is_empty():
			_sink += ab.pop_back()
		best_back = _best(best_back, Time.get_ticks_usec() - t1)
		# --- index cursor: O(n), no mutation ---
		var ai: Array[int] = _make(n)
		var t2: int = Time.get_ticks_usec()
		for i: int in ai.size():
			_sink += ai[i]
		best_index = _best(best_index, Time.get_ticks_usec() - t2)
		# --- swap-back drain: remove index 0 by overwriting it with the last
		# element then dropping the tail — O(1) per removal => O(n) total. This is
		# the SwapBackUtil.remove_at_i32 technique, inlined. Order is destroyed
		# (fine for a drain). PackedInt32Array so it matches the addon's value path.
		var asw: PackedInt32Array = _make_packed(n)
		var t3: int = Time.get_ticks_usec()
		while not asw.is_empty():
			var last: int = asw.size() - 1
			_sink += asw[0]
			asw[0] = asw[last]
			asw.resize(last)
		best_swap = _best(best_swap, Time.get_ticks_usec() - t3)
	var ratio: float = float(best_front) / float(maxi(best_swap, 1))
	print("%d\t%d\t\t%d\t\t%d\t%d\t\t%.1fx" % [n, best_front, best_back, best_index, best_swap, ratio])
