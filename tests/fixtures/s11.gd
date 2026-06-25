extends Node

func _process(_delta: float) -> void:
	print("frame spam") # EXPECT S11
	prints("a", "b") # EXPECT S11


func _physics_process(_delta: float) -> void:
	printerr("phys") # EXPECT S11


func _ready() -> void:
	print("one-shot boot log — not per-frame, not flagged")


func helper(v: int) -> void:
	print(v)
