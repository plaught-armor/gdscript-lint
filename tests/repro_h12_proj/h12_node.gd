# gdlint: disable-file
# Scene node with an @export Resource set to a .tres in the scene file. #110394:
# on load this came back null in affected versions (fixed 4.6).
extends Node

@export var def: Resource
