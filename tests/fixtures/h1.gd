extends Node


func demo() -> void:
	var a := 5  # EXPECT H1
	var b: int = 5
	var c: String = "x := y"
	# comment with := must not flag
	print(a, b, c)
