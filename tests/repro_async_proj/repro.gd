# gdlint: disable-file
extends Node
## Empirically re-tests the await/coroutine lifecycle bugs that need a real frame
## loop (so they can't run under a bare --script custom main loop). Runs as the
## project main scene: godot --headless --path tests/repro_async_proj
##  - C5 (#72629): await across a freed target — confirm the is_instance_valid
##    guard is the working pattern (by design).
##  - C6 (#93608, fixed ~4.7): a coroutine resumed after its owning node is
##    queue_free'd must not crash.

class Flag:
	extends RefCounted
	var resumed: bool = false


class C6Node:
	extends Node
	var flag: Flag


	func start(f: Flag) -> void:
		await get_tree().create_timer(0.02).timeout
		# Resumes after this node was queue_free'd — historically crashed. Write to
		# a RefCounted the caller still holds (this node is freed by now), so we can
		# prove the resume actually ran rather than being silently dropped.
		f.resumed = true


func _ready() -> void:
	await _c5()
	await _c6()
	get_tree().quit()


func _c5() -> void:
	var target: Node = Node.new()
	add_child(target)
	target.free() # freed before the await resumes
	await get_tree().create_timer(0.02).timeout
	var valid: bool = is_instance_valid(target)
	# By design: after the await, is_instance_valid(freed) is false, so the guard
	# blocks a use-after-free. Touching target.* without the guard would crash.
	print("C5     %-14s | is_instance_valid(freed-across-await)=%s (want false → guard works)" % ["CONFIRMED" if not valid else "CHANGED", str(valid)])


func _c6() -> void:
	var flag: Flag = Flag.new()
	var n: C6Node = C6Node.new()
	add_child(n)
	n.start(flag) # fire-and-forget coroutine that awaits a timer
	n.queue_free() # free the owner while the coroutine is suspended
	await get_tree().create_timer(0.05).timeout # let the coroutine's timer fire
	# No crash AND flag.resumed proves the coroutine actually resumed (not dropped).
	print("C6     %-14s | coroutine resumed after owner queue_free (resumed=%s, no crash) (#93608 fixed ~4.7)" % ["CONFIRMED" if flag.resumed else "DROPPED", str(flag.resumed)])
