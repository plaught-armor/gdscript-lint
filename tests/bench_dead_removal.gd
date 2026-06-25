# gdlint: disable-file
extends SceneTree
## How should you remove the dead entries from a list each frame? Four strategies,
## swept over list size N and the fraction that died this pass. "Dead" is intrinsic
## to the value (value % period == 0) so every strategy removes the same logical
## set from a fresh copy.
##
##   swap-back   : swap each dead with the last, shrink. O(n). ORDER LOST.
##   compact     : write-pointer partition — copy survivors forward in place,
##                 resize. O(n). ORDER KEPT. Single pass, no alloc, no dead-list.
##   filter      : append survivors to a NEW array. O(n) + one allocation.
##   remove_at   : remove_at(i) per dead — O(n) shift each => O(n*k). The trap.
##
## Best-of-REPS, fresh array per rep, accumulated into a sink.
## Run: godot --headless --script tests/bench_dead_removal.gd

const REPS: int = 9

var _sink: int = 0


func _initialize() -> void:
	print("dead-entity removal — us to cull one pass (best-of-%d). period: dead = id %% p == 0." % REPS)
	print("N\tdead%\tswap-back\tcompact\t\tfilter\t\tremove_at")
	for n: int in [1000, 10000]:
		_run(n, 2) # ~50% dead
		_run(n, 20) # ~5% dead
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _make(n: int) -> PackedInt32Array:
	var a: PackedInt32Array = []
	a.resize(n)
	for i: int in n:
		a[i] = i + 1 # 1..n; dead-ness = value % period
	return a


func _swap_back(src: PackedInt32Array, period: int) -> int:
	var a: PackedInt32Array = src.duplicate()
	var i: int = 0
	while i < a.size():
		if a[i] % period == 0:
			a[i] = a[a.size() - 1]
			a.resize(a.size() - 1) # don't advance i: re-check the swapped-in value
		else:
			i += 1
	return a.size()


func _compact(src: PackedInt32Array, period: int) -> int:
	var a: PackedInt32Array = src.duplicate()
	var w: int = 0
	for r: int in a.size():
		if a[r] % period != 0:
			a[w] = a[r]
			w += 1
	a.resize(w)
	return a.size()


func _filter(src: PackedInt32Array, period: int) -> int:
	var a: PackedInt32Array = src.duplicate()
	var out: PackedInt32Array = []
	for r: int in a.size():
		if a[r] % period != 0:
			out.append(a[r])
	return out.size()


func _remove_at(src: PackedInt32Array, period: int) -> int:
	var a: PackedInt32Array = src.duplicate()
	var i: int = 0
	while i < a.size():
		if a[i] % period == 0:
			a.remove_at(i) # O(n) shift of the tail, every time
		else:
			i += 1
	return a.size()


func _time(src: PackedInt32Array, period: int, which: int) -> int:
	var best: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		var kept: int = 0
		if which == 0:
			kept = _swap_back(src, period)
		elif which == 1:
			kept = _compact(src, period)
		elif which == 2:
			kept = _filter(src, period)
		else:
			kept = _remove_at(src, period)
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += kept
	return best


func _run(n: int, period: int) -> void:
	var src: PackedInt32Array = _make(n)
	var dead_pct: int = int(round(100.0 / float(period)))
	var sb: int = _time(src, period, 0)
	var cp: int = _time(src, period, 1)
	var fl: int = _time(src, period, 2)
	var ra: int = _time(src, period, 3)
	print("%d\t%d\t%d\t\t%d\t\t%d\t\t%d" % [n, dead_pct, sb, cp, fl, ra])
