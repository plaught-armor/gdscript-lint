# gdlint: disable-file
extends SceneTree
## Backs style.md S9: `if not x` is NOT a null check. It is true for the whole
## falsy set — null, 0, 0.0, "", [], {}, false, AND zero-vectors — while
## `x == null` is true only for null. They agree only when x is an Object/Node
## ref. Also checks the freed-Node case (H8, #59816, fixed 4.4), and times the two
## predicates: `== null` is marginally cheaper (it skips the truthiness bool-cast),
## but the gap is noise-floor — pick on correctness, not speed.
##   Run: godot --headless --script tests/repro_null_checks.gd

const N: int = 2_000_000
const REPS: int = 7
var _sink: int = 0


func _initialize() -> void:
	print("value            not x    x == null")
	_row("null", null)
	_row("int 0", 0)
	_row("int 5", 5)
	_row("float 0.0", 0.0)
	_row("String ''", "")
	_row("String 'a'", "a")
	_row("empty Array", [])
	_row("Array [1]", [1])
	_row("empty Dict", { })
	_row("bool false", false)
	_row("Vector2.ZERO", Vector2.ZERO)
	_row("Vector3.ZERO", Vector3.ZERO)

	var live: Node = Node.new()
	get_root().add_child(live)
	print("freed Node (H8): live  not=%s ==null=%s valid=%s" % [not live, live == null, is_instance_valid(live)])
	live.free()
	print("freed Node (H8): freed not=%s ==null=%s valid=%s" % [not live, live == null, is_instance_valid(live)])

	# perf: predicate cost, best-of-REPS. == null skips the bool-cast `not` pays.
	var node: Node = Node.new()
	get_root().add_child(node)
	var v: Variant = null
	print("perf (best-of-%d, N=%d):" % [REPS, N])
	print("  typed Node ref: not=%d us  ==null=%d us" % [_best(_bench_not.bind(node)), _best(_bench_eq.bind(node))])
	print("  Variant null  : not=%d us  ==null=%d us" % [_best(_bench_not.bind(v)), _best(_bench_eq.bind(v))])
	print("sink=%d" % _sink)
	quit()


func _row(label: String, v: Variant) -> void:
	print("%-16s %-8s %s" % [label, str(not v), str(v == null)])


func _bench_not(x) -> void:
	var acc: int = 0
	for i: int in N:
		acc += 1 if not x else 0
	_sink += acc


func _bench_eq(x) -> void:
	var acc: int = 0
	for i: int in N:
		acc += 1 if x == null else 0
	_sink += acc


func _best(c: Callable) -> int:
	var best: int = 1 << 62
	for r: int in REPS:
		var t0: int = Time.get_ticks_usec()
		c.call()
		var dt: int = Time.get_ticks_usec() - t0
		if dt < best:
			best = dt
	return best
