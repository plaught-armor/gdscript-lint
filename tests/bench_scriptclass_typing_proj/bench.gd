# gdlint: disable-file
extends SceneTree
## Does static typing pay off on SCRIPT-CLASS types the way it does on builtins?
## tests/bench_static_typing.gd only ever measured `int`/`float` locals, so the
## repo's ~25-47% headline is a builtin-arithmetic number. This asks the separate
## question for a `class_name`'d GDScript type, across the shapes a record is
## actually used in: member read, member write, method call, param pass.
##
## Every pair does identical work; only the declaration differs. The untyped side
## reads its reference out of an untyped Array *outside* the timed loop, so the
## compiler cannot recover the type by inference and the var is a true Variant.
## Row `int builtin` is the positive control: the known typed-vs-untyped win has to
## reproduce in this same harness, otherwise the harness is measuring nothing.
##
## Rows, and what each one isolates:
##   int builtin        positive control — the builtin win must reproduce here
##   member read        typed access off an already-typed reference
##   member write       same, store direction (comes back a flat wash)
##   method call        typed call off an already-typed reference
##   param pass         crossing into a typed param, body dereferences a member
##   param, no deref    same call, body returns a constant — separates the
##                      call-site argument check from the member access
##   cast from Variant  Variant source → typed local (OPCODE_ASSIGN_TYPED_SCRIPT,
##                      whose check is entirely inside #ifdef DEBUG_ENABLED)
##   `as` cast          OPCODE_CAST_TO_SCRIPT, whose inheritance walk is OUTSIDE
##                      that #ifdef and so survives a release build
##   local assign       typed local from an already-typed source, no check needed
## Then a depth probe: the same instance cast to targets at increasing distance up
## its own chain, to confirm the unconditional walk is what the `as` row measures.
##
## READING THE OUTPUT. Take the median of ~15 runs, and scrub contaminated runs
## WHOLESALE. A contended machine inflates every row of a run together, so judging
## each row against its own min/max lets one bad run leak a fake tail into a single
## row: that is how `cast from Variant` once looked like "-6%, range -16 to +31%"
## when it is really -8% and entirely negative. Filter used: median of all of a run's
## untyped baselines plus the depth baseline; drop the whole run if it exceeds the
## session median by >10% (1 run in 15, typically).
## Do NOT use `member write` alone as the tell. It should read flat, but at 16-17 ns
## absolute a 0.3 ns jitter is already multiple percent, so it false-alarms on good
## runs and stays flat on runs where only one or two rows are locally contaminated.
## Require two independent indicators to move together.
## Two rows never converge and belong in prose as bands, not numbers: `int builtin`
## and `local assign`. Their medians drift between whole SESSIONS on the same machine
## (`int builtin` has landed at +28, +33, +38 and +46% at different times), which a
## positional split-half inside one batch cannot detect, since both halves share that
## session's ambient state. No conclusion here rests on either row.
##
## NOTE: an editor build has DEBUG_ENABLED on, so the ASSIGN_TYPED_SCRIPT rows here
## carry a check that an exported release build does not. Measuring the release side
## needs a template_release built from this commit — installed templates refuse both
## --path and a CWD project (disable_path_overrides), and no installed editor matches
## an installed template version.
##
## Needs a project: `class_name` globals resolve from project.godot, not from a
## bare --script run.
##
## Run: godot --headless --path tests/bench_scriptclass_typing_proj --script bench.gd

const N: int = 2_000_000
const REPS: int = 7

var _sink: int = 0


func take_typed(r: TypedRec) -> int:
	return r.v

func take_untyped(r) -> int:
	return r.v

# Bodies that never touch a member, to separate the call-site argument type check
# from the member access inside. If `param pass` is slower typed purely because a
# typed param is validated on every call, these two show the same gap with none of
# the member-read win mixed in.
func touch_typed(r: TypedRec) -> int:
	return 1

func touch_untyped(r) -> int:
	return 1


func best(c: Callable) -> float:
	var b: float = INF
	for r in REPS:
		var t0: int = Time.get_ticks_usec()
		c.call()
		b = minf(b, float(Time.get_ticks_usec() - t0) * 1000.0 / float(N))
	return b


func report(label: String, untyped_ns: float, typed_ns: float) -> void:
	var delta: float = (untyped_ns / typed_ns - 1.0) * 100.0
	print("  %-18s untyped %7.1f   typed %7.1f   typed is %+.1f%%" % [
		label, untyped_ns, typed_ns, delta,
	])


func _initialize() -> void:
	var rec: TypedRec = TypedRec.new()
	# Launder the reference through an untyped Array so the untyped rows really are
	# Variant-dispatched; done outside every timed loop.
	var box: Array = [rec]
	var rec_u = box[0]
	var num_box: Array = [7]
	var num_u = num_box[0]
	# Typed counterpart to num_u: the control row must read a captured local on BOTH
	# sides, or the untyped side pays an extra dereference the typed side skips and
	# the control over-reports.
	var num_t: int = 7

	# Burn off cold start in best()/Callable/loop machinery. Deliberately content-free:
	# an earlier version read `rec.v`, which primed the TYPED property-get path and not
	# the Variant one, biasing the very comparison this file exists to make. Result
	# discarded. Caveat: this did NOT settle `int builtin` (see READING THE OUTPUT
	# above) — that row shares no opcode with the warm-up and is volatile on its own.
	best(func() -> void:
		for i in N: pass)

	print("ns/op (best-of-%d, N=%d) — positive control first" % [REPS, N])

	report("int builtin",
		best(func() -> void:
			for i in N:
				var a = num_u
				var b = a * 3 - a
				_sink += b),
		best(func() -> void:
			for i in N:
				var a: int = num_t
				var b: int = a * 3 - a
				_sink += b))

	report("member read",
		best(func() -> void:
			for i in N: _sink += rec_u.v),
		best(func() -> void:
			for i in N: _sink += rec.v))

	report("member write",
		best(func() -> void:
			for i in N: rec_u.v = i),
		best(func() -> void:
			for i in N: rec.v = i))

	report("method call",
		best(func() -> void:
			for i in N: _sink += rec_u.bump(i)),
		best(func() -> void:
			for i in N: _sink += rec.bump(i)))

	report("param pass",
		best(func() -> void:
			for i in N: _sink += take_untyped(rec_u)),
		best(func() -> void:
			for i in N: _sink += take_typed(rec)))

	report("param, no deref",
		best(func() -> void:
			for i in N: _sink += touch_untyped(rec_u)),
		best(func() -> void:
			for i in N: _sink += touch_typed(rec)))

	# THE CAST CASE. Source is a genuine Variant both times. Typed side pays a runtime
	# script-type check to land in a `TypedRec` slot; Variant side keeps it boxed and
	# dereferences straight off the Variant. This is the shape the "Variant is faster
	# for script classes" claim is actually about.
	report("cast from Variant",
		best(func() -> void:
			for i in N:
				var x = rec_u
				_sink += x.v),
		best(func() -> void:
			for i in N:
				var x: TypedRec = rec_u
				_sink += x.v))

	report("`as` cast",
		best(func() -> void:
			for i in N: _sink += rec_u.v),
		best(func() -> void:
			for i in N: _sink += (rec_u as TypedRec).v))

	report("local assign",
		best(func() -> void:
			for i in N:
				var x = rec_u
				_sink += x.v),
		best(func() -> void:
			for i in N:
				var x: TypedRec = rec
				_sink += x.v))

	# CAST_TO_SCRIPT depth probe. Same instance (a D4) cast to targets at increasing
	# distance up its own chain: 0 links to reach D4, 4 links to reach DepthBase.
	# Cost scaling with distance = the unconditional inheritance walk, not the
	# debug-only asserts.
	var deep: DepthBase.D4 = DepthBase.D4.new()
	var deep_box: Array = [deep]
	var deep_u = deep_box[0]
	print("cast depth probe, ns/op (same instance, farther target)")
	print("  no cast (baseline) : %.1f" % best(func() -> void:
		for i in N: _sink += deep_u.v))
	print("  as D4  (0 links)   : %.1f" % best(func() -> void:
		for i in N: _sink += (deep_u as DepthBase.D4).v))
	print("  as D2  (2 links)   : %.1f" % best(func() -> void:
		for i in N: _sink += (deep_u as DepthBase.D2).v))
	print("  as DepthBase (4)   : %.1f" % best(func() -> void:
		for i in N: _sink += (deep_u as DepthBase).v))

	print("  sink=%d" % _sink)
	quit()
