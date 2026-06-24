extends Node


func demo(i: int) -> void:
	var a: float = clamp(0.5, 0.0, 1.0)  # EXPECT P22
	var b: float = abs(-0.5)  # EXPECT P22
	var c: int = clamp(i, 0, 9)
	var d: float = clampf(0.5, 0.0, 1.0)
	print(a, b, c, d)
