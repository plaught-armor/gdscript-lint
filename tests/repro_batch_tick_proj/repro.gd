# gdlint: disable-file
extends Node
## Empirically tests Part IV D8: N entities each running their own _physics_process
## vs one manager iterating an Array and calling tick() on each. Measures average
## physics-frame time in two phases (same per-entity work both ways).
## Runs as project main scene: godot --headless --path tests/repro_batch_tick_proj

const N: int = 5000
const WORK: int = 40 # inner work per entity, so the callback cost is visible
const WARM: int = 15
const SAMPLE: int = 120

var _entities: Array[Ent] = []
var _manager_mode: bool = false
var _frame: int = 0
var _last_us: int = 0
var _sum_active: int = 0
var _n_active: int = 0
var _sum_mgr: int = 0
var _n_mgr: int = 0
var _sink: int = 0


class Ent:
	extends Node
	var sink: int = 0


	func _physics_process(_delta: float) -> void:
		for i: int in 40:
			sink += i


	func tick() -> void:
		for i: int in 40:
			sink += i


func _ready() -> void:
	Engine.physics_ticks_per_second = 100000 # uncap so headless runs frames back-to-back
	Engine.max_physics_steps_per_frame = 1000
	for i: int in N:
		var e: Ent = Ent.new()
		e.set_physics_process(true) # phase 1: each entity self-ticks
		add_child(e)
		_entities.append(e)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: int = (now - _last_us) if _last_us != 0 else 0
	_last_us = now
	_frame += 1

	if _manager_mode:
		for e: Ent in _entities:
			e.tick()

	# Phase 1: entities self-tick (frames WARM..WARM+SAMPLE).
	if not _manager_mode and _frame > WARM and dt > 0:
		_sum_active += dt
		_n_active += 1
	# Phase 2: manager loop (after the switch, past its own warmup).
	if _manager_mode and _frame > (2 * WARM + SAMPLE) and dt > 0:
		_sum_mgr += dt
		_n_mgr += 1

	if _frame == WARM + SAMPLE:
		# switch to manager mode: disable per-entity callbacks
		for e: Ent in _entities:
			e.set_physics_process(false)
		_manager_mode = true
		_last_us = 0 # reset delta baseline across the switch

	if _n_mgr >= SAMPLE:
		_report()
		get_tree().quit()


func _report() -> void:
	for e: Ent in _entities:
		_sink += e.sink
	var avg_active: float = float(_sum_active) / float(maxi(_n_active, 1))
	var avg_mgr: float = float(_sum_mgr) / float(maxi(_n_mgr, 1))
	print("D8     per-Node _physics_process avg=%.1f us/frame  manager-loop avg=%.1f us/frame  ratio=%.2fx (>1 = per-Node slower) [N=%d]" % [avg_active, avg_mgr, avg_active / maxf(avg_mgr, 0.001), N])
