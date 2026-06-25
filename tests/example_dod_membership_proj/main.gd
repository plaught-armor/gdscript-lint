# gdlint: disable-file
extends Node
## D2b — membership container by ownership + scope. Two rooms own their enemies.
##   godot --headless --path tests/example_dod_membership_proj  (import first)
##
## Where does the alive-set live?
##   owner-held Array[Enemy] on each Room → scoped, O(1), typed, no global name.
##   tree-global &"alive" group           → both rooms mixed, no scope, alloc/query;
##                                          scoping needs a minted &"roomN_alive" (smell).
##   &"interactable" group                → LEGIT: tree-wide, owner-less, decoupled
##                                          consumer (the player's interact raycast).

func _ready() -> void:
	var rooms: Array[Room] = []
	for r: int in 2:
		var room: Room = Room.new()
		room.room_id = r
		room.name = "Room%d" % r
		add_child(room)
		rooms.append(room)
	rooms[0].spawn(1)
	rooms[0].spawn(2)
	rooms[0].spawn(3)
	rooms[1].spawn(4)
	rooms[1].spawn(5)

	print("[D2b] owner-held array (good) — scoped, O(1), no global name:")
	_print_rooms(rooms)

	# The owner sees the transition: kill enemy 2 in room 0; its array updates
	# locally, nothing tree-global is touched.
	rooms[0].kill(2)
	print("[D2b] after room0.kill(2) — local update only:")
	_print_rooms(rooms)

	# Anti-pattern, shown for contrast: the same membership in ONE tree-global
	# group. A single name spans the whole tree, so both rooms collapse into it.
	for room: Room in rooms:
		for e: Enemy in room.enemies():
			e.add_to_group(&"alive")
	var mixed: Array[Node] = get_tree().get_nodes_in_group(&"alive")
	print("[D2b] tree-global &\"alive\" (anti-pattern) — both rooms collapse:")
	print("[D2b]   total=%d across the whole tree; \"alive in room 0\" is" % mixed.size())
	print("[D2b]   unanswerable without minting &\"room0_alive\" — the smell.")

	# And a tree-global tag has to be pulled by hand or the count desyncs — the
	# discipline the owner-held array never needs (free the room, _alive goes too).
	for n: Node in mixed:
		n.remove_from_group(&"alive")

	# Legit group: a Door per room — tree-wide, owner-less, decoupled consumer.
	for room: Room in rooms:
		var d: Door = Door.new()
		d.name = "%sDoor" % room.name
		room.add_child(d)
		d.add_to_group(&"interactable")
	var hits: Array[Node] = get_tree().get_nodes_in_group(&"interactable")
	print("[D2b] &\"interactable\" (legit group) — tree-wide, owner-less query:")
	print("[D2b]   a player raycast finds %d interactables, owning none. THIS is" % hits.size())
	print("[D2b]   what the global registry is for.")

	get_tree().quit()


func _print_rooms(rooms: Array[Room]) -> void:
	for room: Room in rooms:
		print("[D2b]   room %d alive=%d ids=%s" % [room.room_id, room.alive_count(), room.alive_ids()])
