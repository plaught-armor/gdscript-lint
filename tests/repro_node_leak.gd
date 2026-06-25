# gdlint: disable-file
extends SceneTree
## Empirically confirms C13: a bare Node.new() with no parent and no free() leaks.
## Node is NOT reference-counted (unlike RefCounted), so dropping the only var does
## NOT free it — it must be parented (tree owns it) or freed explicitly. A control
## that frees shows the leak vanish. Run: godot --headless --script tests/repro_node_leak.gd

const NODES: int = 2000

var _sink: int = 0


func _initialize() -> void:
	_c13_leak()
	_c13_freed_control()
	quit()


func _obj_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _c13_leak() -> void:
	var before: int = _obj_count()
	for i: int in NODES:
		var n: Node = Node.new()
		_sink += n.get_instance_id() & 1 # touch it so it isn't optimized away
		# no parent, no free → n goes out of scope but the Node persists
	var leaked: int = _obj_count() - before
	var tag: String = "LIVE" if leaked > NODES / 2 else "FIXED/not-reproduced"
	print("C13    %-22s | created %d unparented Node.new(), dropped refs -> obj delta %d (leak)" % [tag, NODES, leaked])


func _c13_freed_control() -> void:
	var before: int = _obj_count()
	for i: int in NODES:
		var n: Node = Node.new()
		_sink += n.get_instance_id() & 1
		n.free() # explicit free → no leak
	var delta: int = _obj_count() - before
	print("C13ctl %-22s | same loop WITH n.free() -> obj delta %d (want ~0)" % ["CONFIRMED" if delta < NODES / 2 else "UNEXPECTED", delta])
