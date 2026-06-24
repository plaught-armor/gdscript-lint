extends Node


func demo() -> void:
	var a := 5  # gdlint: ignore[H1]
	var b := 6  # EXPECT H1
	var c := 7  # gdlint: ignore
	print(a, b, c)
