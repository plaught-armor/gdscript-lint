# gdlint: disable-file
extends SceneTree
## Empirically re-tests the Part I "version status" for object-lifecycle engine
## bugs on the build we ship against. Each check prints what it observed + a
## verdict (LIVE = reproduces, FIXED = doesn't, CONFIRMED = prescribed-safe
## behavior holds). await/release-export-dependent bugs (C5, C6, C12, C17) aren't
## headless-deterministic and are left to the issue-tracker status.
## Run: godot --headless --script tests/repro_lifecycle.gd

const CYCLES: int = 2000


class RC extends RefCounted:
	var other: RefCounted = null


class Base10:
	var x: int = 0


	func _init() -> void:
		x = 1


class Der10 extends Base10:
	func _init() -> void:
		super()
		x += 1


class Inner9 extends Resource:
	@export var v: int = 0


class Res9 extends Resource:
	@export var arr: Array = []


func _initialize() -> void:
	_c7()
	_c8()
	_h8()
	_c10()
	_m9()
	_c11()
	_c2a()
	_c3_map()
	quit()


func _verdict(id: String, reproduces: bool, observed: String) -> void:
	var tag: String = "LIVE" if reproduces else "FIXED/not-reproduced"
	print("%-6s %-22s | %s" % [id, tag, observed])


func _note(id: String, label: String, observed: String) -> void:
	print("%-6s %-22s | %s" % [id, label, observed])


func _obj_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _c7() -> void:
	var before: int = _obj_count()
	for i: int in CYCLES:
		var a: RC = RC.new()
		var b: RC = RC.new()
		a.other = b
		b.other = a
		# both go out of scope here; cycle keeps refcount > 0
	var after: int = _obj_count()
	var leaked: int = after - before
	# RefCounted has no cycle collector — a mutual cycle should leak (~2*CYCLES)
	_verdict("C7", leaked > CYCLES, "obj delta after dropping %d cycles = %d (leak if ~%d)" % [CYCLES, leaked, 2 * CYCLES])


func _c8() -> void:
	var n: Node = Node.new()
	var id: int = n.get_instance_id()
	n.free()
	var resolved: Object = instance_from_id(id)
	# Safe behavior: lookup of a freed id returns null (the validity-check pattern).
	_note("C8", "CONFIRMED" if resolved == null else "CHANGED", "instance_from_id(freed)=%s (want <null>)" % str(resolved))


func _h8() -> void:
	var n: Node = Node.new()
	n.free()
	var valid: bool = is_instance_valid(n)
	# #59816 fixed 4.4: is_instance_valid(freed) must be false (old versions lied).
	_note("H8", "CONFIRMED" if not valid else "LIVE", "is_instance_valid(freed)=%s (want false)" % str(valid))


func _c10() -> void:
	var d: Der10 = Der10.new()
	# #76938 fixed 4.2: super() in _init runs the base ctor → x==2.
	_note("C10", "CONFIRMED" if d.x == 2 else "LIVE", "super() in _init -> x=%d (want 2)" % d.x)


func _m9() -> void:
	# #74918 is specifically about a *sub-Resource nested inside an Array* not
	# being deep-copied by duplicate(true). A plain-value Array deep-copies anyway,
	# so the nested Resource is what actually exercises the bug.
	var a: Res9 = Res9.new()
	a.arr = [Inner9.new()]
	(a.arr[0] as Inner9).v = 1
	var b: Res9 = a.duplicate(true)
	(b.arr[0] as Inner9).v = 99
	# fixed 4.5: deep-dup copies the nested Resource → original stays 1.
	# bug: the nested Resource is shared → mutating the copy moves the original to 99.
	var shared: bool = (a.arr[0] as Inner9).v != 1
	_verdict("M9", shared, "deep-dup nested Resource: original .v=%d (want 1; 99 if shared)" % (a.arr[0] as Inner9).v)


func _c11() -> void:
	# Stability: sort by key only; do equal-key items keep their original order?
	var arr: Array = [[1, 0], [1, 1], [1, 2], [0, 3], [1, 4]]
	arr.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var order: PackedInt32Array = []
	for pair: Array in arr:
		if pair[0] == 1:
			order.append(pair[1])
	var stable: bool = order == PackedInt32Array([0, 1, 2, 4])
	_note("C11", "stable-here" if stable else "NOT-STABLE", "equal-key order after sort = %s (orig 0,1,2,4; not guaranteed)" % str(order))


func _c2a() -> void:
	var arr: Array[int] = [1, 2, 3]
	arr.make_read_only()
	var ro: bool = arr.is_read_only()
	_note("C2a", "CONFIRMED" if ro else "BROKEN", "make_read_only() -> is_read_only()=%s (mutation would raise)" % str(ro))


func _c3_map() -> void:
	var typed: Array[int] = [1, 2, 3]
	var mapped: Array = typed.map(func(x: int) -> int: return x * 2)
	var elem: int = mapped.get_typed_builtin()
	_verdict("C3.map", elem != TYPE_INT, ".map() typed-element=%d (TYPE_INT=%d, 0=untyped)" % [elem, TYPE_INT])
