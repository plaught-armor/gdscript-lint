class_name SaveSystem
extends RefCounted
## D6 pure transforms + D4 RELATIONAL save. The record is a flat Dictionary of
## per-concern POD (player / inventory / world / meta), not one opaque blob — so
## adding a subsystem adds a field, and a rename doesn't nuke the whole file
## (Resource-graph saves lose data on field rename; a dict record degrades
## gracefully).
##
## SECURITY: serializes with var_to_bytes / bytes_to_var. bytes_to_var defaults to
## allow_objects = false — it REJECTS any encoded Object in the bytes, the safe
## posture. The unsafe path is a *different function* (bytes_to_var_with_objects):
## it constructs a forged Object payload and runs its embedded script on load —
## remote code execution (CVE-2019-10069; str_to_var and ConfigFile still have no
## safe gate at all, #80562). NEVER call the _with_objects variant on a save a
## player could swap. Binary keeps full type fidelity (Vector2i, PackedStringArray)
## — JSON would collapse ints to floats and lose the Godot types.
##
## COMPRESSION: the binary blob is zstd-compressed before write. Measured
## (tests/bench_save_proj/bench_save.gd, 4.8.dev): store_var is the fastest
## encoder with full type fidelity, and although its raw blob is the largest form,
## zstd shrinks it to ~4-10% — smaller than JSON's raw bytes. zstd beats
## deflate/gzip on ratio AND speed here; fastlz is fastest but ~4x worse ratio.
## So binary store_var + zstd is the smallest-on-disk AND fastest option for a
## Godot-only save. Two gotchas baked into the code below:
##   1. PackedByteArray.decompress(mode) needs the ORIGINAL size — there's no size
##      in the zstd frame Godot writes, so we store_64 the uncompressed length as
##      an 8-byte header. (decompress_dynamic avoids this but rejects zstd/fastlz.)
##   2. Godot hardcodes zstd level 3 (#77820) — ratios trail the cmd-line tool.
##      Crank ProjectSettings compression/formats/zstd/{compression_level,
##      long_distance_matching} for fatter saves; costs ~nothing at save-file sizes.

const VERSION: int = 2
const COMPRESSION: int = FileAccess.COMPRESSION_ZSTD


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
	var blob: PackedByteArray = var_to_bytes(rec) # binary, full Variant fidelity
	var comp: PackedByteArray = blob.compress(COMPRESSION)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_64(blob.size()) # 8-byte header: decompress() needs the original size
	f.store_buffer(comp)
	f.close()
	return DirAccess.rename_absolute(tmp, path)


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { }
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { }
	var orig_size: int = f.get_64() # the header written above
	var comp: PackedByteArray = f.get_buffer(f.get_length() - 8)
	f.close()
	if orig_size <= 0 or comp.is_empty(): # truncated / corrupt file
		return { }
	var blob: PackedByteArray = comp.decompress(orig_size, COMPRESSION)
	# bytes_to_var (not _with_objects) — allow_objects = false, rejects Objects (SAFE)
	var data: Variant = bytes_to_var(blob)
	return data if data is Dictionary else { }
