extends Node

const TABLE: PackedInt32Array = [1, 2]  # EXPECT C1
const OK_INT: int = 5


func demo() -> void:
	var ok: PackedInt32Array = [3, 4]
	print(ok, TABLE, OK_INT)
