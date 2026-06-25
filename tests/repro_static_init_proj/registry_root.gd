# gdlint: disable-file
extends Node
## Autoload (Part V §6). Forces each registry's _static_init by referencing it in
## _ready, in a fixed order. The interleaving of "[RR] about to reference X" with
## "[static_init] X RUNS" reveals WHEN _static_init fires relative to the
## reference — lazy-on-first-touch vs already-run-at-load.

func _ready() -> void:
	print("[RR] _ready START")
	print("[RR] about to reference ItemRegistry")
	var a: int = ItemRegistry.all_defs.size()
	print("[RR] referenced ItemRegistry (size=%d)" % a)
	print("[RR] about to reference EnemyRegistry")
	var b: int = EnemyRegistry.all_defs.size()
	print("[RR] referenced EnemyRegistry (size=%d)" % b)
	print("[RR] _ready END (UnusedRegistry deliberately NOT referenced)")
