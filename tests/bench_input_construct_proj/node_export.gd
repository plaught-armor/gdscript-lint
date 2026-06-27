extends Node
## Inspector path: `ev` is configured in the .tscn as an inline InputEventKey
## sub-resource (the "set it up in the inspector ahead of runtime" case). On
## instantiate(), Godot deserializes that sub-resource and assigns it to `ev`.

@export var ev: InputEventKey
