# gdlint: disable-file
extends Node
## Investigation: is it better to centralize per-frame work into one (or a few)
## systems instead of N nodes each running their own _physics_process?
##
## Measures average physics-frame time for three layouts, swept over entity count
## N and per-entity work W:
##   per-node : N nodes, each with its own _physics_process
##   one-mgr  : 1 manager loops an Array[Ent] calling tick(); entities' callbacks off
##   few-mgr  : K=4 managers, each loops N/K entities
##
## W=0 isolates the PURE per-callback dispatch overhead (the ceiling of what
## centralizing can ever save). W=30 is a realistic light per-entity load. The
## ratio per-node/one-mgr tells you how much the engine's per-node callback
## bookkeeping costs relative to the actual work.
##
## Runs as main scene: import once, then
##   godot --headless --path tests/bench_process_centralization_proj

const WARM: int = 12
const SAMPLE: int = 80
const K_FEW: int = 4
const MODE_PER_NODE: int = 0
const MODE_ONE_MGR: int = 1
const MODE_FEW_MGR: int = 2
const MODE_INLINE: int = 3  # manager works flat data inline — NO per-entity nodes/calls

var _trials: Array = []
var _ti: int = -1
var _root: Node = null
var _frame: int = 0
var _last_us: int = 0
var _sum: int = 0
var _samples: int = 0
var _sink: int = 0
var _results: Array = []


class Ent:
	extends Node
	var work: int = 0
	var sink: int = 0


	func _physics_process(_delta: float) -> void:
		var w: int = work
		for i: int in w:
			sink += i


	func tick() -> void:
		var w: int = work
		for i: int in w:
			sink += i


class Manager:
	extends Node
	var ents: Array[Ent] = []


	func _physics_process(_delta: float) -> void:
		for e: Ent in ents:
			e.tick()


class InlineManager:
	extends Node
	## The DOD shape: no per-entity nodes at all. State is a flat PackedInt32Array;
	## the per-frame work runs INLINE over it — no e.tick() method call per entity.
	var data: PackedInt32Array = []
	var w: int = 0

	func setup(n: int, work: int) -> void:
		data.resize(n)
		w = work

	func _physics_process(_delta: float) -> void:
		var ww: int = w
		for slot: int in data.size():
			var s: int = data[slot]
			for i: int in ww:
				s += i
			data[slot] = s


func _ready() -> void:
	Engine.physics_ticks_per_second = 100000 # uncap: run physics frames back-to-back
	Engine.max_physics_steps_per_frame = 1000
	# Order: manager modes FIRST, per-node LAST. If per-node still wins from this
	# disadvantaged position (CPU warms over a run → later trials favored), the
	# per-node result is robust against the A/B-ordering bias that inflates a
	# "manager faster" verdict when per-node is always measured first.
	for n: int in [1000, 10000]:
		for w: int in [0, 30]:
			_trials.append({ "mode": MODE_ONE_MGR, "n": n, "w": w })
			_trials.append({ "mode": MODE_FEW_MGR, "n": n, "w": w })
			_trials.append({ "mode": MODE_INLINE, "n": n, "w": w })
			_trials.append({ "mode": MODE_PER_NODE, "n": n, "w": w })
	_start_next_trial()
	set_physics_process(true)


func _start_next_trial() -> void:
	_ti += 1
	if _ti >= _trials.size():
		_report()
		get_tree().quit()
		return
	var t: Dictionary = _trials[_ti]
	_root = Node.new()
	add_child(_root)
	if t["mode"] == MODE_INLINE:
		# DOD shape: no per-entity nodes — one node owns a flat array, works it inline.
		var im: InlineManager = InlineManager.new()
		im.setup(t["n"], t["w"])
		_root.add_child(im)
	else:
		var ents: Array[Ent] = []
		for i: int in t["n"]:
			var e: Ent = Ent.new()
			e.work = t["w"]
			e.set_physics_process(t["mode"] == MODE_PER_NODE)
			_root.add_child(e)
			ents.append(e)
		if t["mode"] == MODE_ONE_MGR:
			var m: Manager = Manager.new()
			m.ents = ents
			_root.add_child(m)
		elif t["mode"] == MODE_FEW_MGR:
			var per: int = int(ceil(float(t["n"]) / float(K_FEW)))
			for k: int in K_FEW:
				var m: Manager = Manager.new()
				m.ents = ents.slice(k * per, mini((k + 1) * per, ents.size()))
				_root.add_child(m)
	_frame = 0
	_last_us = 0
	_sum = 0
	_samples = 0


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: int = (now - _last_us) if _last_us != 0 else 0
	_last_us = now
	_frame += 1
	if _frame > WARM and _frame <= WARM + SAMPLE and dt > 0:
		_sum += dt
		_samples += 1
	if _frame > WARM + SAMPLE:
		var avg: float = float(_sum) / float(maxi(_samples, 1))
		_results.append({ "t": _trials[_ti], "avg": avg })
		_root.free()
		_root = null
		_start_next_trial()


func _mode_name(mode: int) -> String:
	if mode == MODE_PER_NODE:
		return "per-node"
	if mode == MODE_ONE_MGR:
		return "one-mgr "
	if mode == MODE_FEW_MGR:
		return "few-mgr "
	return "inline  "


func _report() -> void:
	print("process-centralization — avg us/physics-frame (lower = faster). N x W matrix.")
	print("N\tW\tlayout\t\tus/frame\tvs per-node")
	var base: Dictionary = { } # (n,w) -> per-node avg, for the ratio column
	for r: Dictionary in _results:
		var t: Dictionary = r["t"]
		if t["mode"] == MODE_PER_NODE:
			base[Vector2i(t["n"], t["w"])] = r["avg"]
	for r: Dictionary in _results:
		var t: Dictionary = r["t"]
		var b: float = base[Vector2i(t["n"], t["w"])]
		var ratio: float = b / maxf(r["avg"], 0.001)
		print(
			(
					"%d\t%d\t%s\t%.1f\t\t%.2fx"
					% [t["n"], t["w"], _mode_name(t["mode"]), r["avg"], ratio]
			),
		)
