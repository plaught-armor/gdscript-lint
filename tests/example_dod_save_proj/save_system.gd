class_name SaveSystem
extends RefCounted
## D6 pure transforms + D4 RELATIONAL save. The record is a flat Dictionary of
## per-concern POD (player / inventory / world / meta), not one opaque blob — so
## adding a subsystem adds a field, and a rename doesn't nuke the whole file
## (Resource-graph saves lose data on field rename; a dict record degrades
## gracefully).
##
## SECURITY: uses FileAccess.store_var / get_var. get_var(allow_objects = false)
## REJECTS any encoded Object in the bytes — that's the safe posture. Pass true and
## a forged Object payload is constructed and its embedded script runs on load:
## remote code execution (CVE-2019-10069; note str_to_var and ConfigFile still have
## no safe gate at all, #80562). NEVER pass true on a save a player could swap.
## Binary store_var also keeps full type fidelity (Vector2i, PackedStringArray) —
## JSON would collapse ints to floats and lose the Godot types.

const VERSION: int = 2


static func to_record(s: GameState) -> Dictionary:
	return {
		"version": VERSION,
		"player_pos": s.player_pos,
		"inventory": s.inventory,
		"doors_opened": s.doors_opened,
		"play_seconds": s.play_seconds,
	}


# Additive-with-defaults migration: every field read via .get(key, default), so a
# v1 save that predates `play_seconds` loads clean (defaulted) instead of crashing.
static func from_record(rec: Dictionary) -> GameState:
	var s: GameState = GameState.new()
	s.player_pos = rec.get("player_pos", Vector2.ZERO)
	s.inventory.assign(rec.get("inventory", [])) # untyped wire form → typed (C3)
	s.doors_opened = rec.get("doors_opened", PackedStringArray())
	s.play_seconds = rec.get("play_seconds", 0) # v2 field; absent in a v1 save
	return s


# Atomic write: store to a .tmp then rename over the real file, so a crash
# mid-write leaves the previous save intact. (OS-crash / power-loss safety needs
# fsync, which isn't portable before Godot PR #98361 — double-buffer slots for that.)
static func write(path: String, rec: Dictionary) -> Error:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(rec) # binary, full Variant fidelity, no allow_objects = true
	f.close()
	return DirAccess.rename_absolute(tmp, path)


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { }
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { }
	var data: Variant = f.get_var(false) # allow_objects = false — SAFE
	f.close()
	return data if data is Dictionary else { }
