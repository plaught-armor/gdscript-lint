# gdlint: disable-file
extends SceneTree
## Empirically tests C4 (#83876, "closed-completed — re-test"): Array[T] variance.
## Two questions: (a) does Array[Base] accept a Derived element? (b) can you assign
## Array[Derived] to Array[Base]? Run: godot --headless --script tests/repro_c4_covariance.gd

class Base4:
	extends RefCounted
	var tag: String = "base"


class Der4:
	extends Base4
	var extra: int = 1


func _initialize() -> void:
	# (a) element covariance — Der4 IS-A Base4, so this should be allowed.
	var base_arr: Array[Base4] = []
	base_arr.append(Der4.new())
	print("C4a    element-covariance   | Array[Base4].append(Der4) -> size=%d (Der4 is-a Base4)" % base_arr.size())

	# (b) array covariance — assign Array[Der4] to Array[Base4]. If GDScript is
	# invariant this is a compile/runtime error; if covariant it succeeds.
	var der_arr: Array[Der4] = [Der4.new(), Der4.new()]
	var as_base: Variant = der_arr
	var assignable: bool = false
	if as_base is Array:
		var probe: Array[Base4] = []
		# assign() performs a checked element-wise copy; reports if conversion holds
		probe.assign(der_arr)
		assignable = probe.size() == der_arr.size()
	print("C4b    array-assign          | assign(Array[Der4]) into Array[Base4] -> ok=%s size=%d" % [str(assignable), der_arr.size()])

	# (c) DIRECT covariant assignment is rejected at COMPILE time on 4.8.dev — it
	# can't be exercised at runtime here because it never parses. The line:
	#     var as_base: Array[Base4] = der_arr
	# yields: "Parse Error: Cannot assign a value of type Array[Der4] to variable
	# 'as_base' with specified type Array[Base4]." So typed arrays are INVARIANT;
	# #83876 resolves to a loud compile error, not a silent bug. Use assign() (b).
	print("C4c    array-covariance      | direct Array[Base4] = Array[Der4] is a COMPILE error (invariant) — use assign()")
	quit()
