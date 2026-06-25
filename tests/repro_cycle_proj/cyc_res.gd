# gdlint: disable-file
# Data Resource that points back at a scene — the inverse edge that forms the
# .tres -> .tscn -> .tres cycle (C17 / #98551).
class_name CycRes
extends Resource

@export var label: String = "cyc-res"
@export var scene: PackedScene
