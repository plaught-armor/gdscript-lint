extends SceneTree
## Inspector-authored vs code-constructed object: is there a runtime cost
## difference? Answers the question "does configuring an object in the inspector
## ahead of runtime save the program construction work?" — NO: a scene/resource is
## DATA on disk, rehydrated (parsed -> constructed -> property-set) on every load.
## The object is built each run either way.
##
## PRIMARY comparison — the actual inspector question, at scene-instantiation
## granularity: instantiate() a PackedScene that carries the @export already
## applied vs one that generates the object in code. The result INVERTS on whether
## the sub-resource is shared, which the _ev_shared() check proves first:
##
##   inst_code         — node_code.tscn: ev built in _init() (generate during
##                       instantiate). Distinct object per instance.
##   inst_postload     — node_postload.tscn: ev null after instantiate, built by a
##                       build() call AFTER load ("load the scene then generate").
##                       Distinct per instance; ~= inst_code (timing-of-generation
##                       doesn't move the number).
##   inst_export       — node_export.tscn: @export InputEventKey set inline in the
##                       .tscn. Default sub-resource is SHARED across all instances
##                       → instantiate() just ref-assigns the one cached object.
##                       Cheapest, but every instance aliases it (mutation footgun).
##   inst_export_local — same, but resource_local_to_scene = true → engine
##                       DUPLICATES the sub-resource per instance. Distinct, and the
##                       honest apples-to-apples vs code: ~3.5x SLOWER than inst_code.
##
## So "export applied vs generate" is not one number: shared+cheap+aliased
## (default export) vs distinct+pricier+isolated (local export / code). Pick by
## mutation semantics first, perf second.
##
## MECHANISM breakdown — four ways to obtain the bare InputEventKey, isolating the
## deserialize-vs-construct unit cost without the surrounding Node:
##
##   1. code        — InputEventKey.new() + set fields  (pure code path)
##   2. load_cached — load() with CACHE_MODE_REUSE       (hashmap lookup, ONE shared
##                                                        instance handed to all callers)
##   3. load_ignore — load() with CACHE_MODE_IGNORE      (fresh deserialize each call:
##                                                        the inspector-authored unit cost)
##   4. duplicate   — load template once, .duplicate()   (alloc + field copy, N distinct)
##
## Measurement hygiene: each timed loop is INLINE (no per-op Callable — at ~100ns
## ops a Callable.call dispatch ~hundreds of ns would swamp and equalize the
## results). OS file cache is pre-warmed so load_ignore measures parse+construct,
## not cold disk IO. A _sink accumulator defeats dead-code elimination.
##
## Run: godot --headless --path . -s bench_input_construct.gd
## Env: BENCH_ITERS (default 100000), BENCH_ROUNDS (best-of, min wins, default 7).

const DEFAULT_ITERS: int = 100000
const DEFAULT_ROUNDS: int = 7
const RES_PATH: String = "res://input_event.tres"
const SCENE_EXPORT: String = "res://node_export.tscn"
const SCENE_EXPORT_LOCAL: String = "res://node_export_local.tscn"
const SCENE_CODE: String = "res://node_code.tscn"
const SCENE_POSTLOAD: String = "res://node_postload.tscn"

var _sink: int = 0


func _initialize() -> void:
	var iters: int = _env_int("BENCH_ITERS", DEFAULT_ITERS)
	var rounds: int = _env_int("BENCH_ROUNDS", DEFAULT_ROUNDS)

	# Pre-warm: populate ResourceLoader cache + OS page cache so load_ignore times
	# parse+construct, not the cold first-read disk hit.
	var template: Resource = load(RES_PATH)
	var packed_export: PackedScene = load(SCENE_EXPORT) as PackedScene
	var packed_export_local: PackedScene = load(SCENE_EXPORT_LOCAL) as PackedScene
	var packed_code: PackedScene = load(SCENE_CODE) as PackedScene
	var packed_postload: PackedScene = load(SCENE_POSTLOAD) as PackedScene
	if (
			template == null
			or packed_export == null
			or packed_export_local == null
			or packed_code == null
			or packed_postload == null
	):
		push_error("[bench] could not load fixtures")
		quit(1)
		return

	# THE CRUX: is the @export sub-resource shared across instances, or distinct?
	# Default .tscn sub-resource = SHARED (one object, all instances ref it → cheap
	# but a mutation footgun). resource_local_to_scene = true → duplicated per
	# instance (distinct, the apples-to-apples vs code build).
	print("\nsub-resource sharing across instantiate():")
	print("  node_export.tscn        ev shared = %s" % _ev_shared(packed_export))
	print("  node_export_local.tscn  ev shared = %s" % _ev_shared(packed_export_local))

	# PRIMARY: instantiate() — the @export sub-resource (inspector) vs _init() code,
	# inside real scene instantiation. Node alloc is paid by all → delta isolates
	# the deserialize-and-assign vs construct-in-code work.
	var inst_export_us: int = _bench_instantiate(rounds, iters, packed_export)
	var inst_export_local_us: int = _bench_instantiate(rounds, iters, packed_export_local)
	var inst_code_us: int = _bench_instantiate(rounds, iters, packed_code)
	var inst_postload_us: int = _bench_instantiate_postload(rounds, iters, packed_postload)

	# MECHANISM: the bare InputEventKey, no surrounding Node.
	var code_us: int = _bench_code(rounds, iters)
	var cached_us: int = _bench_load_cached(rounds, iters)
	var ignore_us: int = _bench_load_ignore(rounds, iters)
	var dup_us: int = _bench_duplicate(rounds, iters, template)

	var inst_base_ns: float = float(inst_code_us) * 1000.0 / iters
	var base_ns: float = float(code_us) * 1000.0 / iters
	print("\n=== InputEventKey: inspector @export vs code-constructed ===")
	print("iters=%d  rounds=%d (best-of, min wins)  sink=%d\n" % [iters, rounds, _sink])

	print("PRIMARY — scene instantiate() (Node alloc paid by all):")
	print("  %-16s %12s   %8s" % ["path", "ns/op", "vs code"])
	print("  %s" % "-".repeat(40))
	_row("inst_code", inst_code_us, iters, inst_base_ns)
	_row("inst_postload", inst_postload_us, iters, inst_base_ns)
	_row("inst_export", inst_export_us, iters, inst_base_ns)
	_row("inst_export_local", inst_export_local_us, iters, inst_base_ns)

	print("\nMECHANISM — bare InputEventKey, no Node:")
	print("  %-14s %12s   %8s" % ["path", "ns/op", "vs code"])
	print("  %s" % "-".repeat(38))
	_row("code", code_us, iters, base_ns)
	_row("load_cached", cached_us, iters, base_ns)
	_row("duplicate", dup_us, iters, base_ns)
	_row("load_ignore", ignore_us, iters, base_ns)
	print("")
	quit(0)


func _bench_instantiate(rounds: int, iters: int, packed: PackedScene) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var n: Node = packed.instantiate()
			var ev: InputEventKey = n.get(&"ev") as InputEventKey
			sink += ev.keycode
			n.free()
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _bench_code(rounds: int, iters: int) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var ev: InputEventKey = InputEventKey.new()
			ev.keycode = KEY_A
			ev.physical_keycode = KEY_A
			ev.unicode = 97
			ev.pressed = true
			sink += ev.keycode
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _bench_load_cached(rounds: int, iters: int) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var ev: InputEventKey = load(RES_PATH) as InputEventKey
			sink += ev.keycode
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _bench_load_ignore(rounds: int, iters: int) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var ev: InputEventKey = (
					ResourceLoader.load(RES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as InputEventKey
			)
			sink += ev.keycode
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _bench_duplicate(rounds: int, iters: int, template: Resource) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var ev: InputEventKey = template.duplicate() as InputEventKey
			sink += ev.keycode
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _bench_instantiate_postload(rounds: int, iters: int, packed: PackedScene) -> int:
	var best: int = 1 << 62
	var sink: int = 0
	for r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		for i: int in iters:
			var n: Node = packed.instantiate()
			n.call(&"build")
			var ev: InputEventKey = n.get(&"ev") as InputEventKey
			sink += ev.keycode
			n.free()
		best = mini(best, Time.get_ticks_usec() - t0)
	_sink += sink
	return best


func _ev_shared(packed: PackedScene) -> bool:
	var a: Node = packed.instantiate()
	var b: Node = packed.instantiate()
	var ea: InputEventKey = a.get(&"ev") as InputEventKey
	var eb: InputEventKey = b.get(&"ev") as InputEventKey
	var same: bool = ea != null and eb != null and ea.get_instance_id() == eb.get_instance_id()
	a.free()
	b.free()
	return same


func _row(label: String, usec: int, iters: int, base_ns: float) -> void:
	var ns: float = float(usec) * 1000.0 / iters
	print("  %-16s %9.1f ns/op   %6.2fx" % [label, ns, ns / base_ns])


func _env_int(key: String, fallback: int) -> int:
	if not OS.has_environment(key):
		return fallback
	return int(OS.get_environment(key))
