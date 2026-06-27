extends Node
## Post-load generate: the scene carries NO ev; instantiate() leaves it null, and
## the caller builds it in build() AFTER load (your "load the scene then generate"
## case). Construction work is identical to node_code.gd — only the WHEN differs
## (a called method post-instantiate vs _init during instantiate), so this isolates
## whether timing-of-generation moves the number (it does not).

var ev: InputEventKey


func build() -> void:
	ev = InputEventKey.new()
	ev.keycode = KEY_A
	ev.physical_keycode = KEY_A
	ev.unicode = 97
	ev.pressed = true
