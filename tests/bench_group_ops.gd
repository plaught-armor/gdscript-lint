# gdlint: disable-file
extends SceneTree
## Backs Part IV D2a: SceneTree groups are HashMap-backed, so membership ops are
## cheap O(1) — the only footgun is get_nodes_in_group(), which allocates a fresh
## Array on every call (a problem only inside a per-frame loop).
##
## Measures, per call:
##   - add_to_group / remove_from_group (toggle)
##   - is_in_group(&"tag")
##   - is_in_group(&"player")  vs  `node is Player`   (D2a: prefer the class check)
##   - get_first_node_in_group (no alloc)
##   - get_nodes_in_group      (allocs a fresh Array each call) vs a cached Array
## Best-of-REPS, accumulated into _sink.
##
## Run: godot --headless --script tests/bench_group_ops.gd

const N: int = 1_000_000
const REPS: int = 7
const GROUP_SIZE: int = 200

var _sink: float = 0.0


class Player extends Node:
	pass


func _initialize() -> void:
	var nodes: Array[Node] = []
	for i: int in GROUP_SIZE:
		var n: Node = Node.new()
		get_root().add_child(n)
		n.add_to_group(&"mob")
		nodes.append(n)
	var player: Player = Player.new()
	player.add_to_group(&"player")
	get_root().add_child(player)
	var probe: Node = nodes[0]

	_bench_add_remove(probe)
	_bench_is_in_group(probe)
	_bench_is_class_vs_group(player)
	_bench_get_first()
	_bench_get_nodes_vs_cached()

	for n: Node in nodes:
		n.queue_free()
	player.queue_free()
	quit()


func _best(a: int, b: int) -> int:
	return a if a < b else b


func _bench_add_remove(probe: Node) -> void:
	var best: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			probe.add_to_group(&"tmp")
			probe.remove_from_group(&"tmp")
		best = _best(best, Time.get_ticks_usec() - t0)
	print("D2a  add+remove_from_group  = %d us  -> %.1f ns/pair" % [best, float(best) * 1000.0 / float(N)])


func _bench_is_in_group(probe: Node) -> void:
	var best: int = 1 << 60
	for rep: int in REPS:
		var cnt: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			if probe.is_in_group(&"mob"):
				cnt += 1
		best = _best(best, Time.get_ticks_usec() - t0)
		_sink += float(cnt)
	print("D2a  is_in_group(&\"mob\")    = %d us  -> %.1f ns/call" % [best, float(best) * 1000.0 / float(N)])


func _bench_is_class_vs_group(player: Player) -> void:
	var node: Node = player
	var best_grp: int = 1 << 60
	var best_cls: int = 1 << 60
	for rep: int in REPS:
		var c0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			if node.is_in_group(&"player"):
				c0 += 1
		best_grp = _best(best_grp, Time.get_ticks_usec() - t0)
		var c1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			if node is Player:
				c1 += 1
		best_cls = _best(best_cls, Time.get_ticks_usec() - t1)
		_sink += float(c0 + c1)
	print(
		(
				"D2a  is_in_group(&\"player\")=%d us  `is Player`=%d us  ratio=%.2fx"
				% [best_grp, best_cls, float(best_grp) / float(best_cls)]
		),
	)


func _bench_get_first() -> void:
	var best: int = 1 << 60
	for rep: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var n: Node = get_first_node_in_group(&"mob")
			if n != null:
				_sink += 0.0
		best = _best(best, Time.get_ticks_usec() - t0)
	print("D2a  get_first_node_in_group= %d us  -> %.1f ns/call" % [best, float(best) * 1000.0 / float(N)])


func _bench_get_nodes_vs_cached() -> void:
	const ITERS: int = 50_000 # fewer: each call allocs an Array of GROUP_SIZE
	var cached: Array[Node] = get_nodes_in_group(&"mob")
	var best_alloc: int = 1 << 60
	var best_cached: int = 1 << 60
	for rep: int in REPS:
		var c0: int = 0
		var t0: int = Time.get_ticks_usec()
		for i: int in ITERS:
			var arr: Array[Node] = get_nodes_in_group(&"mob")
			c0 += arr.size()
		best_alloc = _best(best_alloc, Time.get_ticks_usec() - t0)
		var c1: int = 0
		var t1: int = Time.get_ticks_usec()
		for i: int in ITERS:
			c1 += cached.size()
		best_cached = _best(best_cached, Time.get_ticks_usec() - t1)
		_sink += float(c0 + c1)
	print(
		(
				"D2a  get_nodes_in_group(alloc)=%d us  cached-Array=%d us  ratio=%.1fx  (%d calls, group=%d)"
				% [best_alloc, best_cached, float(best_alloc) / float(best_cached), ITERS, GROUP_SIZE]
		),
	)
