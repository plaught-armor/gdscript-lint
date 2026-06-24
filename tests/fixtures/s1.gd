extends Node


func demo() -> void:
	var f: Callable = func(): return 1  # EXPECT S1
	print(f.call())


func named(x: int) -> int:
	return x
