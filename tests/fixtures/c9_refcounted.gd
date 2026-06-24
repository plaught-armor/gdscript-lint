# no-godot-validate (Godot rejects native-method overrides — that IS the C9 bug)
extends RefCounted


func get_name() -> String:
	return "domain name"


func get_class() -> String:  # EXPECT C9
	return "x"