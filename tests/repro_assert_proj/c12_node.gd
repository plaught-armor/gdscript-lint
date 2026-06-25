# gdlint: disable-file
extends Node
## Empirically tests C12: assert() (and its argument expression) is stripped in
## release builds. The assert calls _side(), which sets a flag. In a DEBUG build
## the flag is set (assert ran); in a RELEASE build the whole assert is compiled
## out, so the flag stays false — proving any side effect inside assert() is lost.
## Run under both builds (see repro.sh / the Part I C12 note):
##   editor (debug):  godot.linuxbsd.editor.x86_64 --headless --path tests/repro_assert_proj
##   release template: linux_release.x86_64        --headless --path tests/repro_assert_proj

var _ran: bool = false


func _side() -> bool:
	_ran = true
	return true


func _ready() -> void:
	assert(_side(), "C12 assert body — present in debug, stripped in release")
	var mode: String = "release" if OS.has_feature("release") else "debug"
	print("C12    %-8s | is_debug=%s  assert-body-ran=%s (debug:true / release:false=stripped)" % [mode, str(OS.is_debug_build()), str(_ran)])
	get_tree().quit()
