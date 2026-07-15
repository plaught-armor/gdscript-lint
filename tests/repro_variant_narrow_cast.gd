# gdlint: disable-file
extends SceneTree
## Backs style.md H14c (+ reviewer H14c): narrowing a Variant that already holds
## type T with `x as T` vs the constructor `T(x)`. The measured verdict is that the
## choice is IDIOM ONLY — perf and safety are a wash:
##   - PERF: PackedByteArray is copy-on-write, so NEITHER form copies bytes on the
##     read path — both share the buffer and bump a refcount. Timed here at ~1.0x
##     (see _timing). An earlier guess that the ctor "copies real bytes" is FALSE.
##   - MUTATION: writing to the result COW-copies for either form equally; the
##     source stays intact both ways (see _behavior's mutate check).
##   - SAFETY: both fail loud on a true mismatch — `42 as PackedByteArray` ->
##     "Invalid cast", `PackedByteArray(42)` -> "Nonexistent constructor". Neither
##     silently degenerates.
## So prefer `as` for readability (it reads as a narrow, not a conversion), not for
## speed or correctness. Caveat: on a genuinely DIFFERENT type `as` does a real
## conversion (`[1,2,3] as PackedByteArray` = Array -> Packed), same as the ctor.
##   Run: godot --headless --script tests/repro_variant_narrow_cast.gd
##
## This file times + demonstrates; it does not assert. Durable finding = the ~1.0x
## RATIO (no copy either way), not the absolute microseconds, which drift.

const N: int = 200_000
const BLOB_BYTES: int = 65_536 # 64 KiB — big enough that a per-call copy shows up


func _initialize() -> void:
	_behavior()
	print("")
	_timing()
	quit(0)


func _behavior() -> void:
	print("=== behavior ===")
	# A Variant that already holds a PackedByteArray (element of an untyped Array,
	# like the args a request_completed handler stashed).
	var boxed: Array = [0, 0, 0, PackedByteArray([104, 105])] # [3] = "hi"
	var v: Variant = boxed[3]

	var narrowed: PackedByteArray = v as PackedByteArray
	print("narrow (as):  is_packed=", typeof(narrowed) == TYPE_PACKED_BYTE_ARRAY, " val=", narrowed.get_string_from_utf8())

	var built: PackedByteArray = PackedByteArray(v)
	print("ctor:         is_packed=", typeof(built) == TYPE_PACKED_BYTE_ARRAY, " val=", built.get_string_from_utf8())

	# `as` on a genuinely different type converts + copies — same as the ctor.
	var plain: Array = [104, 105]
	var converted: PackedByteArray = plain as PackedByteArray
	print("Array as Packed (convert, NOT narrow): is_packed=", typeof(converted) == TYPE_PACKED_BYTE_ARRAY)
	# An incompatible type hard-fails BOTH ways: `42 as PackedByteArray` -> Invalid
	# cast; `PackedByteArray(42)` -> Nonexistent constructor. Neither degenerates.

	# COW: mutating either result copies-on-write; the shared source stays intact,
	# and it stays intact identically whether the sibling came from `as` or the ctor.
	var src: PackedByteArray = PackedByteArray([1, 2, 3])
	var shared: Array = [src]
	var via_as: PackedByteArray = shared[0] as PackedByteArray
	var via_ctor: PackedByteArray = PackedByteArray(shared[0])
	via_as.append(99)
	print("after mutate via_as: src=", src, " via_as=", via_as, " via_ctor=", via_ctor, " (src/via_ctor stay [1, 2, 3])")


func _timing() -> void:
	print("=== timing (", N, " reps, ", BLOB_BYTES, "-byte blob) ===")
	var blob: PackedByteArray = []
	blob.resize(BLOB_BYTES)
	var boxed: Array = [blob] # untyped Array -> boxed[0] reads back as Variant
	var sink: int = 0

	var t0: int = Time.get_ticks_usec()
	for i: int in N:
		var narrowed: PackedByteArray = boxed[0] as PackedByteArray
		sink += narrowed.size()
	var t_as: int = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	for i: int in N:
		var built: PackedByteArray = PackedByteArray(boxed[0])
		sink += built.size()
	var t_ctor: int = Time.get_ticks_usec() - t0

	print("as-narrow: ", t_as, " us")
	print("ctor:      ", t_ctor, " us")
	print("ratio ctor/as: ", "%.2f" % (float(t_ctor) / float(maxi(t_as, 1))), "x  (~1.0 => COW, neither copies bytes)")
	print("sink=", sink)
