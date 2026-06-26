# gdlint: disable-file
extends SceneTree
## Does member-var TYPE change RefCounted .new() cost, or does Variant flatten it?
## Fixed 20 vars/class, all one type. POD types inline into the Variant tagged union;
## heap-backed types (String/Array/Dict/Transform3D/Basis/Packed*) allocate backing per
## instance. Per-var-of-type cost = (variant ns - empty base) / 20. Repeated alloc:
## each iter overwrites _hold so prior frees — alloc+free per iter, N times.
##
## Run: godot --headless --script tests/bench_refcounted_vartype.gd

const N: int = 1_000_000
const REPS: int = 7
const COUNT: int = 20

var _hold: RefCounted = null
var _sink: int = 0


class Empty extends RefCounted:
	pass


class T0 extends RefCounted:
	var v0
	var v1
	var v2
	var v3
	var v4
	var v5
	var v6
	var v7
	var v8
	var v9
	var v10
	var v11
	var v12
	var v13
	var v14
	var v15
	var v16
	var v17
	var v18
	var v19

class T1 extends RefCounted:
	var v0: int = 0
	var v1: int = 0
	var v2: int = 0
	var v3: int = 0
	var v4: int = 0
	var v5: int = 0
	var v6: int = 0
	var v7: int = 0
	var v8: int = 0
	var v9: int = 0
	var v10: int = 0
	var v11: int = 0
	var v12: int = 0
	var v13: int = 0
	var v14: int = 0
	var v15: int = 0
	var v16: int = 0
	var v17: int = 0
	var v18: int = 0
	var v19: int = 0

class T2 extends RefCounted:
	var v0: float = 0.0
	var v1: float = 0.0
	var v2: float = 0.0
	var v3: float = 0.0
	var v4: float = 0.0
	var v5: float = 0.0
	var v6: float = 0.0
	var v7: float = 0.0
	var v8: float = 0.0
	var v9: float = 0.0
	var v10: float = 0.0
	var v11: float = 0.0
	var v12: float = 0.0
	var v13: float = 0.0
	var v14: float = 0.0
	var v15: float = 0.0
	var v16: float = 0.0
	var v17: float = 0.0
	var v18: float = 0.0
	var v19: float = 0.0

class T3 extends RefCounted:
	var v0: bool = false
	var v1: bool = false
	var v2: bool = false
	var v3: bool = false
	var v4: bool = false
	var v5: bool = false
	var v6: bool = false
	var v7: bool = false
	var v8: bool = false
	var v9: bool = false
	var v10: bool = false
	var v11: bool = false
	var v12: bool = false
	var v13: bool = false
	var v14: bool = false
	var v15: bool = false
	var v16: bool = false
	var v17: bool = false
	var v18: bool = false
	var v19: bool = false

class T4 extends RefCounted:
	var v0: Vector2 = Vector2.ZERO
	var v1: Vector2 = Vector2.ZERO
	var v2: Vector2 = Vector2.ZERO
	var v3: Vector2 = Vector2.ZERO
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector2 = Vector2.ZERO
	var v6: Vector2 = Vector2.ZERO
	var v7: Vector2 = Vector2.ZERO
	var v8: Vector2 = Vector2.ZERO
	var v9: Vector2 = Vector2.ZERO
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector2 = Vector2.ZERO
	var v12: Vector2 = Vector2.ZERO
	var v13: Vector2 = Vector2.ZERO
	var v14: Vector2 = Vector2.ZERO
	var v15: Vector2 = Vector2.ZERO
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector2 = Vector2.ZERO
	var v18: Vector2 = Vector2.ZERO
	var v19: Vector2 = Vector2.ZERO

class T5 extends RefCounted:
	var v0: Vector3 = Vector3.ZERO
	var v1: Vector3 = Vector3.ZERO
	var v2: Vector3 = Vector3.ZERO
	var v3: Vector3 = Vector3.ZERO
	var v4: Vector3 = Vector3.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: Vector3 = Vector3.ZERO
	var v7: Vector3 = Vector3.ZERO
	var v8: Vector3 = Vector3.ZERO
	var v9: Vector3 = Vector3.ZERO
	var v10: Vector3 = Vector3.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: Vector3 = Vector3.ZERO
	var v13: Vector3 = Vector3.ZERO
	var v14: Vector3 = Vector3.ZERO
	var v15: Vector3 = Vector3.ZERO
	var v16: Vector3 = Vector3.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: Vector3 = Vector3.ZERO
	var v19: Vector3 = Vector3.ZERO

class T6 extends RefCounted:
	var v0: Vector4 = Vector4.ZERO
	var v1: Vector4 = Vector4.ZERO
	var v2: Vector4 = Vector4.ZERO
	var v3: Vector4 = Vector4.ZERO
	var v4: Vector4 = Vector4.ZERO
	var v5: Vector4 = Vector4.ZERO
	var v6: Vector4 = Vector4.ZERO
	var v7: Vector4 = Vector4.ZERO
	var v8: Vector4 = Vector4.ZERO
	var v9: Vector4 = Vector4.ZERO
	var v10: Vector4 = Vector4.ZERO
	var v11: Vector4 = Vector4.ZERO
	var v12: Vector4 = Vector4.ZERO
	var v13: Vector4 = Vector4.ZERO
	var v14: Vector4 = Vector4.ZERO
	var v15: Vector4 = Vector4.ZERO
	var v16: Vector4 = Vector4.ZERO
	var v17: Vector4 = Vector4.ZERO
	var v18: Vector4 = Vector4.ZERO
	var v19: Vector4 = Vector4.ZERO

class T7 extends RefCounted:
	var v0: Color = Color()
	var v1: Color = Color()
	var v2: Color = Color()
	var v3: Color = Color()
	var v4: Color = Color()
	var v5: Color = Color()
	var v6: Color = Color()
	var v7: Color = Color()
	var v8: Color = Color()
	var v9: Color = Color()
	var v10: Color = Color()
	var v11: Color = Color()
	var v12: Color = Color()
	var v13: Color = Color()
	var v14: Color = Color()
	var v15: Color = Color()
	var v16: Color = Color()
	var v17: Color = Color()
	var v18: Color = Color()
	var v19: Color = Color()

class T8 extends RefCounted:
	var v0: RefCounted = null
	var v1: RefCounted = null
	var v2: RefCounted = null
	var v3: RefCounted = null
	var v4: RefCounted = null
	var v5: RefCounted = null
	var v6: RefCounted = null
	var v7: RefCounted = null
	var v8: RefCounted = null
	var v9: RefCounted = null
	var v10: RefCounted = null
	var v11: RefCounted = null
	var v12: RefCounted = null
	var v13: RefCounted = null
	var v14: RefCounted = null
	var v15: RefCounted = null
	var v16: RefCounted = null
	var v17: RefCounted = null
	var v18: RefCounted = null
	var v19: RefCounted = null

class T9 extends RefCounted:
	var v0: String = ""
	var v1: String = ""
	var v2: String = ""
	var v3: String = ""
	var v4: String = ""
	var v5: String = ""
	var v6: String = ""
	var v7: String = ""
	var v8: String = ""
	var v9: String = ""
	var v10: String = ""
	var v11: String = ""
	var v12: String = ""
	var v13: String = ""
	var v14: String = ""
	var v15: String = ""
	var v16: String = ""
	var v17: String = ""
	var v18: String = ""
	var v19: String = ""

class T10 extends RefCounted:
	var v0: StringName = &""
	var v1: StringName = &""
	var v2: StringName = &""
	var v3: StringName = &""
	var v4: StringName = &""
	var v5: StringName = &""
	var v6: StringName = &""
	var v7: StringName = &""
	var v8: StringName = &""
	var v9: StringName = &""
	var v10: StringName = &""
	var v11: StringName = &""
	var v12: StringName = &""
	var v13: StringName = &""
	var v14: StringName = &""
	var v15: StringName = &""
	var v16: StringName = &""
	var v17: StringName = &""
	var v18: StringName = &""
	var v19: StringName = &""

class T11 extends RefCounted:
	var v0: Transform3D = Transform3D()
	var v1: Transform3D = Transform3D()
	var v2: Transform3D = Transform3D()
	var v3: Transform3D = Transform3D()
	var v4: Transform3D = Transform3D()
	var v5: Transform3D = Transform3D()
	var v6: Transform3D = Transform3D()
	var v7: Transform3D = Transform3D()
	var v8: Transform3D = Transform3D()
	var v9: Transform3D = Transform3D()
	var v10: Transform3D = Transform3D()
	var v11: Transform3D = Transform3D()
	var v12: Transform3D = Transform3D()
	var v13: Transform3D = Transform3D()
	var v14: Transform3D = Transform3D()
	var v15: Transform3D = Transform3D()
	var v16: Transform3D = Transform3D()
	var v17: Transform3D = Transform3D()
	var v18: Transform3D = Transform3D()
	var v19: Transform3D = Transform3D()

class T12 extends RefCounted:
	var v0: Basis = Basis()
	var v1: Basis = Basis()
	var v2: Basis = Basis()
	var v3: Basis = Basis()
	var v4: Basis = Basis()
	var v5: Basis = Basis()
	var v6: Basis = Basis()
	var v7: Basis = Basis()
	var v8: Basis = Basis()
	var v9: Basis = Basis()
	var v10: Basis = Basis()
	var v11: Basis = Basis()
	var v12: Basis = Basis()
	var v13: Basis = Basis()
	var v14: Basis = Basis()
	var v15: Basis = Basis()
	var v16: Basis = Basis()
	var v17: Basis = Basis()
	var v18: Basis = Basis()
	var v19: Basis = Basis()

class T13 extends RefCounted:
	var v0: Array = []
	var v1: Array = []
	var v2: Array = []
	var v3: Array = []
	var v4: Array = []
	var v5: Array = []
	var v6: Array = []
	var v7: Array = []
	var v8: Array = []
	var v9: Array = []
	var v10: Array = []
	var v11: Array = []
	var v12: Array = []
	var v13: Array = []
	var v14: Array = []
	var v15: Array = []
	var v16: Array = []
	var v17: Array = []
	var v18: Array = []
	var v19: Array = []

class T14 extends RefCounted:
	var v0: Array[int] = []
	var v1: Array[int] = []
	var v2: Array[int] = []
	var v3: Array[int] = []
	var v4: Array[int] = []
	var v5: Array[int] = []
	var v6: Array[int] = []
	var v7: Array[int] = []
	var v8: Array[int] = []
	var v9: Array[int] = []
	var v10: Array[int] = []
	var v11: Array[int] = []
	var v12: Array[int] = []
	var v13: Array[int] = []
	var v14: Array[int] = []
	var v15: Array[int] = []
	var v16: Array[int] = []
	var v17: Array[int] = []
	var v18: Array[int] = []
	var v19: Array[int] = []

class T15 extends RefCounted:
	var v0: Dictionary = {}
	var v1: Dictionary = {}
	var v2: Dictionary = {}
	var v3: Dictionary = {}
	var v4: Dictionary = {}
	var v5: Dictionary = {}
	var v6: Dictionary = {}
	var v7: Dictionary = {}
	var v8: Dictionary = {}
	var v9: Dictionary = {}
	var v10: Dictionary = {}
	var v11: Dictionary = {}
	var v12: Dictionary = {}
	var v13: Dictionary = {}
	var v14: Dictionary = {}
	var v15: Dictionary = {}
	var v16: Dictionary = {}
	var v17: Dictionary = {}
	var v18: Dictionary = {}
	var v19: Dictionary = {}

class T16 extends RefCounted:
	var v0: PackedInt32Array = []
	var v1: PackedInt32Array = []
	var v2: PackedInt32Array = []
	var v3: PackedInt32Array = []
	var v4: PackedInt32Array = []
	var v5: PackedInt32Array = []
	var v6: PackedInt32Array = []
	var v7: PackedInt32Array = []
	var v8: PackedInt32Array = []
	var v9: PackedInt32Array = []
	var v10: PackedInt32Array = []
	var v11: PackedInt32Array = []
	var v12: PackedInt32Array = []
	var v13: PackedInt32Array = []
	var v14: PackedInt32Array = []
	var v15: PackedInt32Array = []
	var v16: PackedInt32Array = []
	var v17: PackedInt32Array = []
	var v18: PackedInt32Array = []
	var v19: PackedInt32Array = []

class T17 extends RefCounted:
	var v0: PackedByteArray = []
	var v1: PackedByteArray = []
	var v2: PackedByteArray = []
	var v3: PackedByteArray = []
	var v4: PackedByteArray = []
	var v5: PackedByteArray = []
	var v6: PackedByteArray = []
	var v7: PackedByteArray = []
	var v8: PackedByteArray = []
	var v9: PackedByteArray = []
	var v10: PackedByteArray = []
	var v11: PackedByteArray = []
	var v12: PackedByteArray = []
	var v13: PackedByteArray = []
	var v14: PackedByteArray = []
	var v15: PackedByteArray = []
	var v16: PackedByteArray = []
	var v17: PackedByteArray = []
	var v18: PackedByteArray = []
	var v19: PackedByteArray = []


func _time_new(klass: GDScript) -> int:
	var best: int = 1 << 62
	for r: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			_hold = klass.new()
		var dt: int = Time.get_ticks_usec() - t0
		if dt < best:
			best = dt
		_sink += _hold.get_instance_id()
	return best


var _base: int = 0


func _report(label: String, usec: int) -> void:
	var ns_per_new: float = float(usec) * 1000.0 / float(N)
	var over_empty: float = float(usec - _base) * 1000.0 / float(N)
	var per_var: float = over_empty / float(COUNT)
	print("%s  %7.1f ns/new  %+7.1f vs empty  %6.1f ns/var" % [label, ns_per_new, over_empty, per_var])


func _init() -> void:
	_base = _time_new(Empty)
	print("var-TYPE cost — %d vars/class, N=%d, best-of-%d (4.8.dev)" % [COUNT, N, REPS])
	print("empty base: %.1f ns/new" % (float(_base) * 1000.0 / float(N)))
	print("--------------------------------------------------------------------")
	_report("  variant_null", _time_new(T0))
	_report("           int", _time_new(T1))
	_report("         float", _time_new(T2))
	_report("          bool", _time_new(T3))
	_report("       vector2", _time_new(T4))
	_report("       vector3", _time_new(T5))
	_report("       vector4", _time_new(T6))
	_report("         color", _time_new(T7))
	_report("    refcounted", _time_new(T8))
	_report("        string", _time_new(T9))
	_report("    stringname", _time_new(T10))
	_report("   transform3d", _time_new(T11))
	_report("         basis", _time_new(T12))
	_report("         array", _time_new(T13))
	_report(" typed_arr_int", _time_new(T14))
	_report("    dictionary", _time_new(T15))
	_report("  packed_int32", _time_new(T16))
	_report("   packed_byte", _time_new(T17))
	print("--------------------------------------------------------------------")
	print("sink: %d" % _sink)
	quit()
