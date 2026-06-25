# gdlint: disable-file
extends Node
## Empirically re-tests H12 (#110394, fixed 4.6): an @export Resource set in a
## .tscn coming back null after the scene is loaded. Loads scene.tscn, instantiates
## it, and checks whether the node's @export `def` survived the load.
## Runs as the project main scene: godot --headless --path tests/repro_h12_proj

func _ready() -> void:
	var packed: PackedScene = load("res://scene.tscn") as PackedScene
	var inst: Node = packed.instantiate()
	var def: Variant = inst.get("def")
	var ok: bool = def != null
	var v: Variant = def.get("v") if ok else null
	var tag: String = "CONFIRMED fixed" if ok else "LIVE"
	print("H12    %-16s | @export Resource after load = %s (v=%s, want set/7)" % [tag, "set" if ok else "<null>", str(v)])
	inst.free()
	get_tree().quit()
