extends Node

func interact(target: Node) -> void:
	if target.has_method(&"on_use"): # EXPECT H13
		target.call(&"on_use", self)


func safe(target: Node) -> void:
	# has_method with no matching .call() literal — not duck-dispatch, no flag
	if target.has_method(&"ping"):
		target.queue_free()
