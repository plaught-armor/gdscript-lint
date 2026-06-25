# gdlint: disable-file
extends Node
## Observational test for H9 (#71372): does an @onready var's setter fire during
## the @onready initialization, and what is observable at that moment — is a later
## @onready var already assigned, is a child node reachable? Reported neutrally
## (the exact expected behavior of #71372 is the thing under investigation).
## Runs as project main scene: godot --headless --path tests/repro_h9_proj

var _setter_fired: bool = false
var _second_when_first_set: int = -999
var _child_when_first_set: bool = false

@onready var first: int = 1:
	set(value):
		_setter_fired = true
		_second_when_first_set = second # a later @onready var — set yet?
		_child_when_first_set = has_node(^"Child") # is the child reachable?

@onready var second: int = 20


func _ready() -> void:
	var fired_on_onready: bool = _setter_fired
	# Now do a normal assignment to confirm the setter is actually wired.
	_setter_fired = false
	first = 99
	var fired_on_normal_assign: bool = _setter_fired
	print(
		(
				"H9     @onready_fired_setter=%s (false=@onready bypasses it) | normal_assign_fired_setter=%s (true=setter wired)"
				% [str(fired_on_onready), str(fired_on_normal_assign)]
		),
	)
	get_tree().quit()
