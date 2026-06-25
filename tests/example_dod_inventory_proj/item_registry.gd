class_name InvItemRegistry
extends RefCounted
## D11 — the anti-mirror. A naive design carries parallel arrays keyed by Id:
##   static var DEFS: Array[InvItemDef]      # the data
##   static var ICONS: Array[Texture2D]      # mirror #1
##   static var SCENES: Array[PackedScene]   # mirror #2
## ...each of which must stay length-aligned with Id, guarded by a parity test
## (`assert ICONS.size() == Id.size()`). That test is the smell. This registry
## has ONE table; the icon path is DERIVED by convention (D7a), and per-item
## constants (max_stack) are folded into InvItemDef. No second array, no parity.
## C2a — the one table is locked read-only after build (shallow: the InvItemDef
## instances stay mutable — Resource has no freeze API, so immutability there is
## convention-only).

enum Id { POTION, ETHER, SWORD, SHIELD }

static var defs: Array[InvItemDef] = [
	InvItemDef.new(&"potion", 99),
	InvItemDef.new(&"ether", 99),
	InvItemDef.new(&"sword", 1),
	InvItemDef.new(&"shield", 1),
]


static func _static_init() -> void:
	if not defs.is_read_only():
		defs.make_read_only()


# Public API is a boundary (D10a): enum-typed, but GDScript won't stop a caller
# passing a raw out-of-range int, so the registry validates and fails loud (C12:
# push_error, never assert — assert is stripped in release).
static func get_def(id: Id) -> InvItemDef:
	if id < 0 or id >= defs.size():
		push_error("[InvItemRegistry] invalid Id: %d" % id)
		return null
	return defs[id]


# D7a — convention-derived dispatch in its canonical form: an if/elif chain
# returning string LITERALS (interned → genuinely allocation-free, unlike a
# "%s"-formatted path), with a per-slot override point and a loud empty default.
# No parallel ICONS array to keep aligned (D11). A boot validator would
# ResourceLoader.exists() each — omitted here for brevity.
static func icon_path(id: Id) -> String:
	if id == Id.POTION:
		return "res://icons/potion.png"
	if id == Id.ETHER:
		return "res://icons/ether.png"
	if id == Id.SWORD:
		return "res://icons/sword.png"
	if id == Id.SHIELD:
		return "res://icons/shield.png"
	return ""
