# gdlint: disable-file
extends Node
## Empirically tests the await/signal lifecycle traps from Part II that need a real
## frame loop. Runs as project main scene: godot --headless --path tests/repro_async2_proj
##  - M1: await in a method makes it return early; post-await code runs later.
##  - M6: a signal connected to a *temporary* RefCounted's method is silently lost
##        once that object goes out of scope (connections don't keep targets alive).
##  - M7: call_deferred runs at end of frame, not inline.
##  - M8: a tween bound to a node is invalidated when that node is freed.

signal ping

var _after_await: bool = false
var ping_count: int = 0
var _deferred_ran: bool = false


class M6Listener:
	extends RefCounted
	var sink: Node


	func on_ping() -> void:
		sink.ping_count += 1


func _ready() -> void:
	await _m1()
	_m6()
	await _m7()
	await _m8()
	get_tree().quit()


# --- M1 ---
func _run_await() -> void:
	await get_tree().process_frame
	_after_await = true


func _m1() -> void:
	_after_await = false
	_run_await() # fire-and-forget coroutine; not awaited here
	# This line runs immediately — before _run_await resumes past its await.
	print("M1     %-14s | right after calling an awaiting fn: _after_await=%s (false = await deferred it)" % ["CONFIRMED" if not _after_await else "CHANGED", str(_after_await)])
	await get_tree().create_timer(0.05).timeout # let it finish so state is clean


# --- M6 ---
func _connect_temp() -> void:
	var listener: M6Listener = M6Listener.new()
	listener.sink = self
	ping.connect(listener.on_ping)
	# listener's only ref is this local; it drops at function return.


func _m6() -> void:
	_connect_temp()
	var before: int = ping_count
	ping.emit()
	var fired: bool = ping_count > before
	# If the connection kept the listener alive it would fire; it doesn't, so the
	# temp RefCounted is gone and the listener silently never runs.
	print("M6     %-14s | emit after temp-RefCounted listener went out of scope: fired=%s (want false)" % ["CONFIRMED" if not fired else "CHANGED", str(fired)])


# --- M7 ---
func _m7_target() -> void:
	_deferred_ran = true


func _m7() -> void:
	_deferred_ran = false
	call_deferred(&"_m7_target")
	var inline: bool = _deferred_ran
	await get_tree().process_frame
	var after_frame: bool = _deferred_ran
	print("M7     %-14s | call_deferred ran inline=%s (want false), after a frame=%s (want true)" % ["CONFIRMED" if (not inline and after_frame) else "CHANGED", str(inline), str(after_frame)])


# --- M8 ---
func _m8() -> void:
	var n: Node2D = Node2D.new()
	add_child(n)
	var tw: Tween = n.create_tween()
	tw.tween_property(n, ^"position:x", 100.0, 1.0) # real work — an empty tween auto-kills for the wrong reason
	n.queue_free()
	await get_tree().process_frame # frame 0: node now freed, but tween still reports valid
	var valid_f0: bool = tw.is_valid()
	await get_tree().process_frame # frame 1: tween invalidates a frame after the node went away
	var valid_f1: bool = tw.is_valid()
	# Node-bound tween IS invalidated by the node's free — but a frame late, and
	# is_running() keeps returning true even after is_valid() goes false.
	var ok: bool = valid_f0 and not valid_f1
	print("M8     %-14s | node-bound tween after node free: valid@frame0=%s valid@frame1=%s running=%s (invalidates, 1-frame lag)" % ["CONFIRMED" if ok else "CHANGED", str(valid_f0), str(valid_f1), str(tw.is_running())])
