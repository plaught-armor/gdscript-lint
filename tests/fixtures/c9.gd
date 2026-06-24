# no-godot-validate (Godot rejects native-method overrides — that IS the C9 bug)
extends Node2D


func get_name() -> StringName:  # EXPECT C9
	return &"x"


func get_instance_id() -> int:  # EXPECT C9
	return 0


func compute_score() -> int:
	return 1