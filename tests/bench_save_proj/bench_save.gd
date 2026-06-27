extends SceneTree
## Save-serialization bench: store_var (binary Variant) vs JSON, then the
## orthogonal compression layer (fastlz / deflate / zstd / gzip) on the binary
## blob. One logical GameState payload, scaled by inventory size N.
##
## Answers two questions the save rule rests on:
##   1. Which encoder for a Godot-only save? -> store_var (fastest, full type fidelity).
##   2. Is compression worth it, and which? -> zstd (best ratio AND speed here).
##
## Run:
##   godot --headless --path . -s bench_save.gd
##
## Optional env: BENCH_N (inventory items, default 1000), BENCH_ITERS (default 200),
## BENCH_ROUNDS (best-of, min wins, default 7). Pure measurement — writes nothing.

const DEFAULT_N: int = 1000
const DEFAULT_ITERS: int = 200
const DEFAULT_ROUNDS: int = 7

const COMP_NAMES: Dictionary = {
	FileAccess.COMPRESSION_FASTLZ: "fastlz",
	FileAccess.COMPRESSION_DEFLATE: "deflate",
	FileAccess.COMPRESSION_ZSTD: "zstd",
	FileAccess.COMPRESSION_GZIP: "gzip",
}


func _initialize() -> void:
	var n: int = _env_int("BENCH_N", DEFAULT_N)
	var iters: int = _env_int("BENCH_ITERS", DEFAULT_ITERS)
	var rounds: int = _env_int("BENCH_ROUNDS", DEFAULT_ROUNDS)

	var rec: Dictionary = _build_record(n)
	print("=== save serialization bench ===")
	print("payload: GameState + %d inventory items, iters=%d, best-of-%d rounds" % [n, iters, rounds])
	print("")
	print("  encoder       encode ms/it   decode ms/it      bytes   vs store_var")
	print("  ------------  ------------   ------------   ----------  -----------")

	var store_var_bytes: int = _bench_store_var(rec, iters, rounds)
	_bench_json(rec, iters, rounds, store_var_bytes)

	# --- compression layer (orthogonal — wraps the binary blob) -------------
	var blob: PackedByteArray = var_to_bytes(rec)
	print("")
	print("=== compression on the store_var blob (%d bytes) ===" % blob.size())
	print("  mode     ratio    out bytes   compress ms   decompress ms")
	print("  -------  -------   ---------   -----------   -------------")
	for mode: int in [
		FileAccess.COMPRESSION_FASTLZ,
		FileAccess.COMPRESSION_DEFLATE,
		FileAccess.COMPRESSION_ZSTD,
		FileAccess.COMPRESSION_GZIP,
	]:
		_bench_compress(blob, mode, iters, rounds)

	quit(0)

# --- payload -------------------------------------------------------------


## GameState record: scalar header + an inventory list of N {name, count} rows.
## Binary store_var keeps full type fidelity (Vector2 pos, typed ints); JSON
## flattens these — that lossiness is part of what the bench surfaces.
func _build_record(n: int) -> Dictionary:
	var inv: Array = []
	inv.resize(n)
	for i: int in n:
		inv[i] = { "name": "item_%d" % i, "count": (i % 99) + 1 }
	return {
		"version": 1,
		"player_name": "Aria",
		"level": 7,
		"hp": 84,
		"pos": Vector2(12.5, -3.25),
		"inventory": inv,
	}

# --- encoders ------------------------------------------------------------


func _bench_store_var(rec: Dictionary, iters: int, rounds: int) -> int:
	var bytes: PackedByteArray = var_to_bytes(rec)
	var enc_us: int = _best_round(rounds, iters, func() -> void: var _b: PackedByteArray = var_to_bytes(rec))
	var dec_us: int = _best_round(rounds, iters, func() -> void: var _d: Variant = bytes_to_var(bytes))
	_row("store_var", enc_us, dec_us, iters, bytes.size(), bytes.size())
	return bytes.size()


func _bench_json(rec: Dictionary, iters: int, rounds: int, base: int) -> void:
	# JSON can't carry Vector2 / typed ints — flatten pos to floats so the
	# round-trip is even legal. Cheaper bytes, lost types.
	var flat: Dictionary = rec.duplicate(true)
	var p: Vector2 = rec["pos"]
	flat["pos"] = [p.x, p.y]
	var text: String = JSON.stringify(flat)
	var bytes: PackedByteArray = text.to_utf8_buffer()
	var enc_us: int = _best_round(rounds, iters, func() -> void: var _s: String = JSON.stringify(flat))
	var dec_us: int = _best_round(rounds, iters, func() -> void: var _d: Variant = JSON.parse_string(text))
	_row("json (lossy)", enc_us, dec_us, iters, bytes.size(), base)

# --- compression ---------------------------------------------------------


func _bench_compress(blob: PackedByteArray, mode: int, iters: int, rounds: int) -> void:
	var packed: PackedByteArray = blob.compress(mode)
	var orig: int = blob.size()
	var comp_us: int = _best_round(rounds, iters, func() -> void: var _c: PackedByteArray = blob.compress(mode))
	var dec_us: int = _best_round(rounds, iters, func() -> void: var _d: PackedByteArray = packed.decompress(orig, mode))
	print(
		(
				"  %-7s  %5.1f%%   %9d   %9.3f     %9.3f"
				% [
					COMP_NAMES[mode],
					100.0 * packed.size() / orig,
					packed.size(),
					(comp_us / 1000.0) / iters,
					(dec_us / 1000.0) / iters,
				]
		),
	)

# --- harness -------------------------------------------------------------


## Run `iters` calls of `work`, repeat `rounds` times, return fastest round's
## total usec. Min-of-rounds drops scheduler noise (repo BENCH.md convention).
func _best_round(rounds: int, iters: int, work: Callable) -> int:
	work.call() # warm
	var best: int = 1 << 62
	for round_n: int in rounds:
		var start: int = Time.get_ticks_usec()
		for iter_n: int in iters:
			work.call()
		best = mini(best, Time.get_ticks_usec() - start)
	return best


func _row(label: String, enc_us: int, dec_us: int, iters: int, bytes: int, base: int) -> void:
	print(
		(
				"  %-12s  %10.4f   %10.4f   %10d   %8.2fx"
				% [label, (enc_us / 1000.0) / iters, (dec_us / 1000.0) / iters, bytes, float(bytes) / base]
		),
	)


func _env_int(key: String, fallback: int) -> int:
	var raw: String = OS.get_environment(key)
	return fallback if raw.is_empty() else raw.to_int()
