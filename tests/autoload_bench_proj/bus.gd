# gdlint: disable-file
# Autoload singleton. No class_name — the [autoload] key "Bus" is already the
# global identifier (a matching class_name would collide; see Part V).
extends Node

func add(x: int) -> int:
	return x + 1
