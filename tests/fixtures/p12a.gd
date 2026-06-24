extends Node


func demo(d: Dictionary) -> void:
	add_to_group("enemies")  # EXPECT P12a
	if is_in_group("alive"):  # EXPECT P12a
		pass
	add_to_group(&"ok")
	var v: Variant = d.get("key")
	print(v)
