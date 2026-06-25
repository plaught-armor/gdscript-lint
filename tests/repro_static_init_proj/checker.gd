# gdlint: disable-file
extends Node
## Main scene. Autoloads' _ready run BEFORE the main scene, so by here the
## RegistryRoot trace above has already printed. This asserts the post-boot
## invariants: once-only static_init, sentinel, read-only lock.

func _ready() -> void:
	print("== checker (main scene, post-autoload-boot) ==")
	# Once-only: referencing ItemRegistry again must NOT trigger a 2nd
	# "[static_init] ItemRegistry RUNS" line above this point.
	var n: int = ItemRegistry.all_defs.size()
	print("[chk] re-referenced ItemRegistry size=%d (no 2nd static_init line = once-only)" % n)
	# Sentinel: index 0 (Id.NONE) is a deliberate null.
	print("[chk] ItemRegistry.all_defs[0] == null ? %s" % (ItemRegistry.all_defs[0] == null))
	# Read-only lock (C2a) set inside _static_init.
	print("[chk] ItemRegistry.all_defs.is_read_only() ? %s" % ItemRegistry.all_defs.is_read_only())
	# Lazy-vs-eager verdict: UnusedRegistry has class_name but was never
	# referenced. If no "[static_init] UnusedRegistry RUNS" appeared above,
	# static_init is lazy-on-first-reference (bible claim holds).
	print("[chk] UnusedRegistry referenced? NO — check above for its static_init line")
	get_tree().quit()
