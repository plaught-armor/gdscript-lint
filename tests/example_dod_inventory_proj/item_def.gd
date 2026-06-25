class_name InvItemDef
extends Resource
## D1 POD. Crucially for D11: the fields that a naive design would scatter across
## PARALLEL registries (a SCENES array, an ICONS array, a STACKS array — each
## keyed by the same enum Id) live here, in ONE record. max_stack is a folded
## field; the icon path is derived by convention (see InvItemRegistry.icon_path,
## D7a) rather than stored in a second array. One table, no mirrors.

@export var id_name: StringName = &""
@export var max_stack: int = 99


func _init(p_id_name: StringName = &"", p_max_stack: int = 99) -> void:
	id_name = p_id_name
	max_stack = p_max_stack
