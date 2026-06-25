# gdlint: disable-file
# Simple Resource for the ResourceLoader cache repros. No class_name — repro.gd
# accesses it duck-typed so the harness runs headless without a built class cache.
extends Resource

@export var v: int = 5
@export var tags: Array = [1, 2, 3]
