extends Node
## Code path: `ev` is built in _init() (fires during instantiate(), same point the
## @export sub-resource is deserialized in node_export.gd) — apples-to-apples at
## scene-instantiation granularity.

var ev: InputEventKey


func _init() -> void:
	ev = InputEventKey.new()
	ev.keycode = KEY_A
	ev.physical_keycode = KEY_A
	ev.unicode = 97
	ev.pressed = true
