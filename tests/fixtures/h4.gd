extends Node

signal untyped_one(value) # EXPECT H4
signal untyped_mix(target: Node, amount) # EXPECT H4
signal typed_ok(target: Node, amount: int)
signal no_params
signal empty_params()


func _ready() -> void:
	pass
