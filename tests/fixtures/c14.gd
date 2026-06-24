extends Node


func demo() -> void:
	var b: Array[int] = range(10)  # EXPECT C14 S6
	var ok: Array[int] = []  # EXPECT S6
	ok.assign(range(10))
	print(b, ok)
