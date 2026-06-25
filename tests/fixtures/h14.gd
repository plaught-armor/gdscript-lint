extends Node

func narrowed(x: Node) -> void:
	if x is Sprite2D:
		# 'is' already narrowed x to Sprite2D — the cast is a wasted round-trip.
		(x as Sprite2D).flip_h = true # EXPECT H14
		print((x as Sprite2D).position) # EXPECT H14


func binding_is_allowed(x: Node) -> void:
	if x is Sprite2D:
		# H14 explicitly permits 'as' when BINDING to a new var — no parens,
		# not flagged.
		var s: Sprite2D = x as Sprite2D
		s.flip_h = true


func no_narrowing(x: Variant) -> void:
	# No 'if x is T' guard — the cast is a genuine downcast, not redundant.
	(x as Sprite2D).flip_h = true


func different_type(x: Node) -> void:
	if x is Sprite2D:
		# Cast to a DIFFERENT type than the guard — not redundant.
		(x as Node2D).rotation = 0.0


func compound_guard(x: Node, ready: bool) -> void:
	if x is Sprite2D and ready:
		# Compound condition — deliberately not matched (tight guard, zero FP).
		(x as Sprite2D).flip_h = true
