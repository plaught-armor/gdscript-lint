class_name GameState
extends RefCounted
## Runtime POD state (D1). Behavior — serialization — is NOT here; it's a pure
## transform on SaveSystem (D6). Cross-system refs are IDS, not object pointers
## (D3): inventory holds item ids + counts, never ItemDef objects (those would not
## serialize and would dangle). `doors_opened` is a sparse existence-based delta
## (D2/D4): only doors that changed from their default appear — 10k untouched
## doors cost nothing in the save.

var player_pos: Vector2 = Vector2.ZERO
var inventory: Array[Vector2i] = [] # each = (item_id, count) — ids, not objects (D3)
var doors_opened: PackedStringArray = [] # stable door ids that are open (sparse delta)
var play_seconds: int = 0 # added in save v2 — see SaveSystem migration
