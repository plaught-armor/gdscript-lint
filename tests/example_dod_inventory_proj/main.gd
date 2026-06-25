# gdlint: disable-file
extends Node
## Inventory demo. Adds/removes items, shows existence-based contents and the
## convention-derived icon path (one registry, no mirror arrays — D11).
##   godot --headless --path tests/example_dod_inventory_proj  (import first)

func _ready() -> void:
	var inv: Inventory = Inventory.new()

	# Overstack a potion: max_stack is 99, so 120 added → 99 kept, 21 leftover.
	var leftover: int = inv.add(InvItemRegistry.Id.POTION, 120)
	print("[demo] add 120 potion → kept %d, leftover %d" % [inv.count(InvItemRegistry.Id.POTION), leftover])

	inv.add(InvItemRegistry.Id.ETHER, 5)
	inv.add(InvItemRegistry.Id.SWORD, 1)
	# Sword max_stack is 1 — a second sword doesn't fit.
	var sword_left: int = inv.add(InvItemRegistry.Id.SWORD, 1)
	print("[demo] add 2nd sword → count %d, leftover %d" % [inv.count(InvItemRegistry.Id.SWORD), sword_left])

	print("[demo] distinct item kinds carried: %d" % inv.distinct())

	# Remove every ether — the key is erased (existence-based), not left at 0.
	inv.remove(InvItemRegistry.Id.ETHER, 5)
	print("[demo] removed all ether → has ether? %s, distinct now %d" % [inv.has(InvItemRegistry.Id.ETHER), inv.distinct()])

	# D7a — icon paths derived by convention from the single registry, no ICONS array.
	for id: int in [InvItemRegistry.Id.POTION, InvItemRegistry.Id.SWORD]:
		print("[demo] icon(%s) = %s" % [InvItemRegistry.get_def(id).id_name, InvItemRegistry.icon_path(id)])

	get_tree().quit()
