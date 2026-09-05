extends Node

const SECONDS: float = 6.0
const HZ: float = 60.0

# A member initializer that reads a member declared BELOW it gets that field's
# type zero, silently. Every marked line below is that shape.
var out_frame: int = int(SECONDS * HZ)
var end_frame: int = out_frame + 60
var half_frame: int = out_frame / 2

var early: int = late + 1 # EXPECT H15
var multi: int = maxi(late, other_late) # EXPECT H15
var late: int = 42
var other_late: int = 7

# static var is the same story.
static var s_early: int = s_late + 1 # EXPECT H15
static var s_late: int = 7

# A const reads fine in either direction — constant-folded, not initialized in
# order — so neither of these is flagged.
const FOLDED: int = LATER_CONST + 1
const LATER_CONST: int = 100
var from_const: int = FOLDED + LATER_CONST

# @onready runs in _ready, after every plain initializer, so it is not this rule.
@onready var ready_ref: int = plain_below
var plain_below: int = 3

# A lambda body runs when it is called, not at initialization.
var deferred_read: Callable = func() -> int:
	return read_later
var read_later: int = 9

# A method name is not a member var, so calling one declared below is fine.
var from_method: int = _compute()

# Backward references — the working direction, never flagged.
var base_value: int = 5
var derived_value: int = base_value + 10


# A property accessor's body holds LOCALS, not members — and a multi-line func
# signature closes at the header's own indent. Both used to read as class scope.
var guarded: int = 0:
	set(value):
		var probe: int = guarded + later_still
		guarded = maxi(probe, 0)

var later_still: int = 4


func _compute() -> int:
	return 12


func multi_line_signature(first: int, second: int) -> int:
	var local_sum: int = first + second
	return local_sum


func locals_are_not_members() -> void:
	# A local reading a local declared below it is a parse error, not this rule;
	# a local sharing a member's name is still a local. Nothing here is flagged.
	var derived_value: int = base_value
	var scratch: int = derived_value + 1
	print(scratch)


class Inner:
	extends RefCounted

	var forward: int = later # EXPECT H15
	var later: int = 42

	# The outer scope's names are not this scope's — `base_value` is a member of
	# the file's class, not of Inner, so reading it here is not an ordering bug.
	var borrowed: int = 0
