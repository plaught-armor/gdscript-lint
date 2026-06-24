extends Node


func demo(coll: Array) -> void:
	for x in coll:  # EXPECT H2
		print(x)
	for y: int in coll:
		print(y)
