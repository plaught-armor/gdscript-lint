extends Node

var _data: int = 0


func _ready() -> void:
	await get_tree().process_frame # EXPECT M1
	_data = 1
	var x: int = await _fetch() # EXPECT M1
	_data = x


func _fetch() -> int:
	# await OUTSIDE _ready is fine — not flagged.
	await get_tree().process_frame
	return 7


func setup() -> void:
	await get_tree().process_frame
