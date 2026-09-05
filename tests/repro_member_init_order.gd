# gdlint: disable-file
extends SceneTree
## Backs type-async.md H15: member-variable initializers run in DECLARATION
## ORDER, and a forward reference reads the field's type zero-value instead of
## its eventual value — silently, with no warning and no error. `const` is the
## exception: it is constant-folded, so a const may reference one declared below
## it and still read the real value.
##
## Load-bearing wherever one member is derived from another (a harness's frame
## schedule off a dial, a cached bound off a size). The failure is a plausible
## wrong NUMBER, not a crash.
##   Run: godot --headless --script tests/repro_member_init_order.gd

# --- var: forward reference (declared before the field it reads) -------------
var forward_int: int = later_int + 1
var forward_float: float = later_float * 2.0
var forward_obj_is_null: bool = later_obj == null
var forward_arr_size: int = later_arr.size()

var later_int: int = 42
var later_float: float = 10.0
var later_obj: RefCounted = RefCounted.new()
var later_arr: Array[int] = [1, 2, 3]

# --- var: backward reference (the ordinary, working direction) ---------------
var base_int: int = 5
var derived_int: int = base_int + 10

# --- static var: same question ----------------------------------------------
static var s_forward: int = s_later + 1
static var s_later: int = 7
static var s_backward: int = s_later + 1

# --- const: constant-folded, so order does not apply ------------------------
const C_FORWARD: int = C_LATER + 1
const C_LATER: int = 100

# --- a const read from a var initializer (the pattern the rule is about) -----
const DIAL_SECONDS: float = 6.0
var derived_frames: int = int(DIAL_SECONDS * 60.0)


func _initialize() -> void:
	print("var, forward reference (reads the TYPE ZERO, not the value):")
	_row("forward_int      (want 43)", forward_int)
	_row("forward_float    (want 20.0)", forward_float)
	_row("forward_obj_is_null (want false)", forward_obj_is_null)
	_row("forward_arr_size (want 3)", forward_arr_size)

	print("\nvar, backward reference (the working direction):")
	_row("derived_int      (want 15)", derived_int)

	print("\nstatic var:")
	_row("s_forward        (want 8)", s_forward)
	_row("s_backward       (want 8)", s_backward)

	print("\nconst (constant-folded, order-independent):")
	_row("C_FORWARD        (want 101)", C_FORWARD)

	print("\nconst read from a var initializer (always safe):")
	_row("derived_frames   (want 360)", derived_frames)

	print("\nsame question inside _init(), for contrast:")
	var probe: Probe = Probe.new()
	_row("probe.forward    (want 43)", probe.forward)
	_row("probe.in_init    (want 43)", probe.in_init)

	quit(0)


func _row(label: String, value: Variant) -> void:
	print("  %-34s %s" % [label, value])


## An initializer runs before `_init`'s body, so a field that cannot be written
## in declaration order can still be derived correctly one line later.
class Probe extends RefCounted:
	var forward: int = later + 1
	var later: int = 42
	var in_init: int = 0


	func _init() -> void:
		in_init = later + 1
