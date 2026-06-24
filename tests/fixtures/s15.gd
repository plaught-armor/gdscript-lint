extends Node


func demo(name: String, arr: Array) -> void:
	if name == "":  # EXPECT S15
		pass
	if arr.size() == 0:  # EXPECT S15
		pass
	if name == "alive":
		pass
	if name.is_empty():
		pass
