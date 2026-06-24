extends Node


func demo(nodes: Array[Node]) -> void:
	var alive: Array[Node] = nodes.filter(_is_valid)  # EXPECT C3
	var mapped: Array[Node] = nodes.map(_identity)  # EXPECT C3
	var ok: Array[Node] = []
	ok.assign(nodes.filter(_is_valid))
	print(alive, mapped, ok)


func _is_valid(n: Node) -> bool:
	return n != null


func _identity(n: Node) -> Node:
	return n
