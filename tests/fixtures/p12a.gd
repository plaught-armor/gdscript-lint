extends Node

func demo(d: Dictionary) -> void:
	add_to_group("enemies") # EXPECT P12a
	if is_in_group("alive"): # EXPECT P12a
		pass
	add_to_group(&"ok")
	set_meta("hp", 5) # EXPECT P12a
	if has_meta(&"hp"):
		pass
	var sn: StringName = "ident" # EXPECT P12a
	var sn_ok: StringName = &"ident"
	var np: NodePath = "Sprite/Body" # EXPECT P12a
	var np_ok: NodePath = ^"Sprite/Body"
	var v: Variant = d.get("key")
	print(sn, sn_ok, np, np_ok, v)
