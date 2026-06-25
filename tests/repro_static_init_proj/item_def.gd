# gdlint: disable-file
class_name SIItemDef
extends Resource
## Minimal POD Def for the static-init repro. Real registries preload `.tres`;
## here we `.new()` dummies so the project needs no resource files — the element
## type is irrelevant to what this repro measures (static-init timing/order/lock).

var label: String = ""


func _init(p_label: String = "") -> void:
	label = p_label
