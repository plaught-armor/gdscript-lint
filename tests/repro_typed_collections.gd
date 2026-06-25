# gdlint: disable-file
extends SceneTree
## Empirically re-tests the Part I "version status" for the const / typed-collection
## engine bugs on the build we actually ship against. Each check prints what it
## observed + a verdict (LIVE = bug reproduces here, FIXED = it doesn't).
## Run: godot --headless --script tests/repro_typed_collections.gd

# C1 — const Packed*Array (#88753): reports byte-count size, reads 0.0.
const C1_PF: PackedFloat32Array = [1.0, 2.0, 3.0]
# C2 — const Array is a shared mutable ref (#61274).
const C2_ARR: Array = [1, 2, 3]


class C16Base:
	static var v: int = 1


class C16Derived extends C16Base:
	pass


func _initialize() -> void:
	_c1()
	_c2()
	_c3()
	_c14()
	_c16()
	quit()


func _verdict(id: String, reproduces: bool, observed: String) -> void:
	var tag: String = "LIVE" if reproduces else "FIXED/not-reproduced"
	print("%-5s %-22s | %s" % [id, tag, observed])


func _note(id: String, label: String, observed: String) -> void:
	print("%-5s %-22s | %s" % [id, label, observed])


func _c1() -> void:
	var sz: int = C1_PF.size()
	var first: float = C1_PF[0]
	# bug: sz==12 (bytes) and first==0.0; correct: sz==3 and first==1.0
	var buggy: bool = sz != 3 or first != 1.0
	_verdict("C1", buggy, "const PackedFloat32Array size=%d first=%.1f (want size=3 first=1.0)" % [sz, first])


func _c2() -> void:
	var alias: Array = C2_ARR
	alias.append(99)
	var leaked: bool = C2_ARR.size() != 3
	# clean up so re-runs in one process stay sane (process is one-shot anyway)
	if leaked:
		C2_ARR.resize(3)
	_verdict("C2", leaked, "mutating an alias of a const Array changed the const: %s" % str(leaked))


func _c3() -> void:
	var typed: Array[int] = [1, 2, 3, 4]
	var filtered: Variant = typed.filter(func(x: int) -> bool: return x > 2)
	var elem_type: int = (filtered as Array).get_typed_builtin()
	# bug: elem_type==0 (TYPE_NIL / untyped); correct would be TYPE_INT(2)
	var buggy: bool = elem_type != TYPE_INT
	_verdict("C3", buggy, ".filter() typed-element=%d (TYPE_INT=%d, 0=untyped)" % [elem_type, TYPE_INT])


func _c14() -> void:
	var r: Array = range(5)
	var elem_type: int = r.get_typed_builtin()
	# bug: range() yields an untyped Array (elem_type==0), not Array[int]
	var buggy: bool = elem_type != TYPE_INT
	_verdict("C14", buggy, "range(5) typed-element=%d (TYPE_INT=%d, 0=untyped)" % [elem_type, TYPE_INT])


func _c16() -> void:
	C16Base.v = 7
	var via_derived: int = C16Derived.v
	C16Base.v = 1 # reset
	# #87629 is about whether a base static var is shared with subclasses or
	# per-class. Report the observation neutrally rather than asserting a polarity.
	var shared: bool = via_derived == 7
	_note("C16", "shared" if shared else "per-class", "set Base.v=7 -> Derived.v=%d (#87629; shared if 7)" % via_derived)
