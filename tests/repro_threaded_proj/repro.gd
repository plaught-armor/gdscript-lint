# gdlint: disable-file
extends Node
## Empirically tests Part VI RL26: `await ResourceLoader.load_threaded_request(...)`
## is wrong — the function is NOT a coroutine; it returns an Error int, so awaiting
## it hands you that int, not the resource. The correct flow is request → poll
## status → get. Runs as project main scene:
##   godot --headless --path tests/repro_threaded_proj

const P: String = "res://thing.tres"


func _ready() -> void:
	# WRONG: await a non-coroutine. You get its return value (an Error int).
	var bad: Variant = await ResourceLoader.load_threaded_request(P)
	var bad_is_resource: bool = bad is Resource
	print("RL26   await-misuse   | await load_threaded_request -> typeof=%d (TYPE_INT=%d), is_Resource=%s" % [typeof(bad), TYPE_INT, str(bad_is_resource)])

	# RIGHT: request, poll status across frames, then get.
	ResourceLoader.load_threaded_request(P)
	var guard: int = 0
	while ResourceLoader.load_threaded_get_status(P) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and guard < 600:
		await get_tree().process_frame
		guard += 1
	var good: Variant = ResourceLoader.load_threaded_get(P)
	print("RL26   poll+get        | load_threaded_get -> is_Resource=%s (the resource, as intended)" % str(good is Resource))
	get_tree().quit()
