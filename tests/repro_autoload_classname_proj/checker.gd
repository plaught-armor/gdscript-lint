# gdlint: disable-file
extends Node
## Main scene — just boots so the project loads the autoload (whose class_name
## collides). The collision error is emitted by the engine at load time; capture
## it from stderr. Runs as project main scene:
##   godot --headless --path tests/repro_autoload_classname_proj

func _ready() -> void:
	print("A6     booted | watch stderr above for: \"Class 'Foo' hides an autoload singleton\"")
	get_tree().quit()
