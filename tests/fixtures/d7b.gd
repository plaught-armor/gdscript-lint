extends Node


func value_dispatch(w: int) -> int:
	match w:  # EXPECT D7b
		0:
			return 1
		1:
			return 2
		_:
			return 0


func pattern_ok(v: Variant) -> void:
	match v:
		[var a, var b]:
			print(a, b)
		{"key": var val}:
			print(val)
		_:
			pass
