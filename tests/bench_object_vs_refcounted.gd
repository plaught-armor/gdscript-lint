# gdlint: disable-file
extends SceneTree
## Is a bare `Object` lighter than a `RefCounted`? Backs the D9 note on base-class
## choice. Three axes, because the answer differs per axis:
##   1. alloc+free round trip (per instance)
##   2. resident bytes per live instance
##   3. per-COPY cost of a held reference — an Object ref is a raw pointer in a
##      Variant, a RefCounted ref is a Ref<> that runs an atomic inc/dec on every
##      copy, so the copy path is where a refcount could plausibly cost something
## Axis 3 allocates one instance up front and only copies it, so allocation stays
## out of that measurement; each axis-3 sub-benchmark prints an `int` control row
## that is loop overhead to subtract. Best-of-REPS. Rows that *read* a value
## accumulate into _sink. Store rows need no such guard: GDScript never looks for
## dead stores at all — measured, an unread local assignment still costs ~6 ns
## against a ~4 ns empty loop — so liveness of the target is not what keeps them.
##
## The static-dispatch axis (a `class_name`'d helper that is never instantiated)
## needs real global class names, so it lives in tests/bench_objbase_proj/.
##
## Run: godot --headless --script tests/bench_object_vs_refcounted.gd

const N: int = 1_000_000
const REPS: int = 7
const LIVE: int = 100_000
const SLOTS: int = 1024

var _sink: int = 0
var _field_obj: Object = null
var _field_ref: RefCounted = null
var _field_int: int = 0


class ObjEmpty extends Object:
	pass

class RefEmpty extends RefCounted:
	pass

class ObjVars5 extends Object:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO

class RefVars5 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO

class ObjInst extends Object:
	var v: int = 7

class RefInst extends RefCounted:
	var v: int = 7


func take_obj(o: Object) -> int:
	return 1 if o != null else 0

func take_ref(o: RefCounted) -> int:
	return 1 if o != null else 0

func take_int(o: int) -> int:
	return 1 if o != 0 else 0


func best(c: Callable) -> float:
	var b: float = INF
	for r in REPS:
		var t0: int = Time.get_ticks_usec()
		c.call()
		b = minf(b, float(Time.get_ticks_usec() - t0) * 1000.0 / float(N))
	return b


## An Object never drops to zero refs, so the loop frees it by hand; a RefCounted
## falls out of scope and frees itself. Both are one alloc + one free per iter.
func alloc_obj(script: GDScript) -> float:
	return best(func() -> void:
		for i in N:
			var o: Object = script.new()
			_sink += 1 if o != null else 0
			o.free())


func alloc_ref(script: GDScript) -> float:
	return best(func() -> void:
		for i in N:
			var o: RefCounted = script.new()
			_sink += 1 if o != null else 0)


## Coarse: OS.get_static_memory_usage() delta over LIVE instances held in an Array.
## The Array is resized *before* the baseline snapshot, so its per-slot Variant
## storage is already paid for and is excluded from the delta — the figure is the
## instances alone. Still read the Object/RefCounted *difference*, not the absolute.
func mem_per_instance(script: GDScript, is_obj: bool) -> float:
	var hold: Array = []
	hold.resize(LIVE)
	var base: int = OS.get_static_memory_usage()
	for i in LIVE:
		hold[i] = script.new()
	var used: int = OS.get_static_memory_usage() - base
	if is_obj:
		for i in LIVE:
			(hold[i] as Object).free()
	hold.clear()
	return float(used) / float(LIVE)


func _init() -> void:
	print("== 1. alloc+free, ns/op (best-of-%d, N=%d)" % [REPS, N])
	print("  Object     empty : %.1f" % alloc_obj(ObjEmpty))
	print("  RefCounted empty : %.1f" % alloc_ref(RefEmpty))
	print("  Object     5vars : %.1f" % alloc_obj(ObjVars5))
	print("  RefCounted 5vars : %.1f" % alloc_ref(RefVars5))

	print("== 2. bytes/instance (%d live, Array storage excluded — read the delta)" % LIVE)
	print("  Object     empty : %.1f" % mem_per_instance(ObjEmpty, true))
	print("  RefCounted empty : %.1f" % mem_per_instance(RefEmpty, false))

	var oi: ObjInst = ObjInst.new()
	var ri: RefInst = RefInst.new()
	var arr: Array = []
	arr.resize(SLOTS)
	var dict: Dictionary = {}
	for i in SLOTS:
		dict[i] = null

	print("== 3. reference copy, ns/op (alloc excluded, one instance copied)")
	print("  int control      : %.1f  pass to function" % best(func() -> void:
		for i in N: _sink += take_int(7)))
	print("  Object           : %.1f  pass to function" % best(func() -> void:
		for i in N: _sink += take_obj(oi)))
	print("  RefCounted       : %.1f  pass to function" % best(func() -> void:
		for i in N: _sink += take_ref(ri)))

	print("  int control      : %.1f  local assign" % best(func() -> void:
		for i in N:
			var x: int = 7
			_sink += x))
	print("  Object           : %.1f  local assign" % best(func() -> void:
		for i in N:
			var x: Object = oi
			_sink += 1 if x != null else 0))
	print("  RefCounted       : %.1f  local assign" % best(func() -> void:
		for i in N:
			var x: RefCounted = ri
			_sink += 1 if x != null else 0))

	print("  int control      : %.1f  Array slot store" % best(func() -> void:
		for i in N: arr[i & (SLOTS - 1)] = 7))
	print("  Object           : %.1f  Array slot store" % best(func() -> void:
		for i in N: arr[i & (SLOTS - 1)] = oi))
	print("  RefCounted       : %.1f  Array slot store" % best(func() -> void:
		for i in N: arr[i & (SLOTS - 1)] = ri))

	print("  int control      : %.1f  Dictionary store" % best(func() -> void:
		for i in N: dict[i & (SLOTS - 1)] = 7))
	print("  Object           : %.1f  Dictionary store" % best(func() -> void:
		for i in N: dict[i & (SLOTS - 1)] = oi))
	print("  RefCounted       : %.1f  Dictionary store" % best(func() -> void:
		for i in N: dict[i & (SLOTS - 1)] = ri))

	print("  int control      : %.1f  member field store" % best(func() -> void:
		for i in N: _field_int = 7))
	print("  Object           : %.1f  member field store" % best(func() -> void:
		for i in N: _field_obj = oi))
	print("  RefCounted       : %.1f  member field store" % best(func() -> void:
		for i in N: _field_ref = ri))

	arr.clear()
	dict.clear()
	_field_obj = null
	print("  sink=%d" % _sink)
	oi.free()
	quit()
