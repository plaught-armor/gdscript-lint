# gdlint: disable-file
extends Node
## Empirically re-tests C17 (#98551): a .tres -> .tscn -> .tres ext_resource cycle.
## thing.tres has @export scene = thing.tscn; thing.tscn has @export def =
## thing.tres. Loading either should surface whatever the engine does with the
## cycle on 4.8.dev: hang (timeout kills the run), a partial/null field, or a
## clean resolve.
## Runs as the project main scene: godot --headless --path tests/repro_cycle_proj

func _ready() -> void:
	print("C17: loading thing.tres (cycle .tres -> .tscn -> .tres) ...")
	var res: Resource = load("res://thing.tres")
	if res == null:
		print("C17    LOAD-FAILED            | load() returned null")
		get_tree().quit()
		return
	var scene_res: Variant = res.get("scene")
	var scene_ok: bool = scene_res != null
	print("C17a   res.label=%s scene=%s" % [str(res.get("label")), "set" if scene_ok else "<null>"])
	if scene_ok:
		var inst: Node = (scene_res as PackedScene).instantiate()
		var def_back: Variant = inst.get("def")
		var resolved: bool = def_back != null
		print(
			(
					"C17b   instantiated scene; its def back-ref = %s"
					% ("resolved" if resolved else "<null> (partial-load)")
			),
		)
		inst.free()
	# Reaching here at all = no hang. A hang = the bug; timeout would kill us first.
	print("C17    NO-HANG                | cycle resolved without deadlock on 4.8.dev")
	get_tree().quit()
