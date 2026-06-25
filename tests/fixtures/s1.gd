extends Node

func demo() -> void:
	# multi-statement inline lambda — the S1 target (formatter/readability)
	var f: Callable = func(a: int, b: int): # EXPECT S1
		if a > b:
			return a
		return b
	# single-expression lambda — NOT the S1 target, must stay clean
	var g: Callable = func(x: int): return x + 1
	print(f.call(2, 1), g.call(3))


func named(x: int) -> int:
	return x
