# gdlint: disable-file
extends Node
## Save demo. Build a state, save it (atomic, binary, relational), load it back,
## verify the round-trip, then load a hand-crafted v1 save to show the migration
## default. import then --path.

func _ready() -> void:
	var path: String = "user://demo_save.dat"

	# Build a runtime state — ids in the inventory (D3), a sparse door delta (D2).
	var state: GameState = GameState.new()
	state.player_pos = Vector2(128, 64)
	state.inventory = [Vector2i(1, 5), Vector2i(3, 1)] # (item_id, count)
	state.doors_opened = ["room_42/north", "vault/main"]
	state.play_seconds = 3725

	# Save → load round-trip.
	var err: Error = SaveSystem.write(path, SaveSystem.to_record(state))
	print("[demo] wrote save, Error=%d (0 = OK)" % err)
	var loaded: GameState = SaveSystem.from_record(SaveSystem.read(path))
	print("[demo] loaded: pos=%v inv=%s doors=%s play=%ds" % [loaded.player_pos, loaded.inventory, loaded.doors_opened, loaded.play_seconds])

	var ok: bool = (
			loaded.player_pos == state.player_pos
			and loaded.inventory == state.inventory
			and loaded.doors_opened == state.doors_opened
			and loaded.play_seconds == state.play_seconds
	)
	print("[demo] round-trip identical? %s (binary store_var kept Vector2i + types)" % ok)

	# Migration: a v1 save predates `play_seconds`. from_record defaults it, no crash.
	var v1_record: Dictionary = {
		"version": 1,
		"player_pos": Vector2(10, 20),
		"inventory": [Vector2i(2, 9)],
		"doors_opened": PackedStringArray(["start/door"]),
	}
	var migrated: GameState = SaveSystem.from_record(v1_record)
	print("[demo] loaded v1 save → play_seconds defaulted to %d (no crash)" % migrated.play_seconds)

	get_tree().quit()
