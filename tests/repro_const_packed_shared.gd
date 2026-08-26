# gdlint: disable-file
extends SceneTree
## Backs engine-bugs.md C1 (and the "never `const` a `Packed*Array`" half of S6).
##
## The tracker symptom of #88753 — `const Array[PackedFloat32Array]` reporting a
## byte-count size and reading 0.0 — does NOT reproduce on 4.6.stable or 4.8.dev.
## Every const packed shape below reads back its authored contents.
##
## What IS live, and is the reason the rule stands: a `const Packed*Array` is not
## read-only. Binding it to a local and appending mutates the constant itself,
## process-wide, with no error — an independent later binding sees the extra
## element. A `const Array[T]` / `const Dictionary` is read-only on both versions
## and the same mutation raises instead.
##
## Run: godot --headless --script tests/repro_const_packed_shared.gd

const PSA: PackedStringArray = ["a", "b", "c"]
const PFA: PackedFloat32Array = [1.5, 2.5]
const NESTED: Array[PackedFloat32Array] = [[1.5, 2.5], [3.5]]
const ARR: Array[String] = ["a", "b", "c"]
const DICT: Dictionary = {"k": 1}


func _mutate_packed_through_a_binding() -> void:
	var local: PackedStringArray = PSA
	local.append("MUTATED")


func _mutate_typed_through_a_binding() -> void:
	var local: Array[String] = ARR
	local.append("MUTATED") # expected: "Array is in read-only state."


func _initialize() -> void:
	print("--- read-back (#88753 symptom: sizes and values would be wrong) ---")
	print("const PackedStringArray      = %s  size=%d" % [PSA, PSA.size()])
	print("const PackedFloat32Array     = %s  size=%d" % [PFA, PFA.size()])
	print("const Array[PackedFloat32]   = %s  inner0.size=%d" % [NESTED, NESTED[0].size()])

	print("--- read-only state ---")
	print("const Array[String].is_read_only()  = %s" % ARR.is_read_only())
	print("const Dictionary.is_read_only()     = %s" % DICT.is_read_only())
	print("PackedStringArray has no is_read_only()/make_read_only() at all")

	print("--- mutation through a binding ---")
	_mutate_packed_through_a_binding()
	var second: PackedStringArray = PSA
	print("const PackedStringArray after append via a local = %s" % [second])
	_mutate_typed_through_a_binding()
	print("const Array[String] after the same attempt       = %s" % [ARR])
	quit()
