# gdlint: disable-file
# DELIBERATE collision (Part V A6): this script is registered as the autoload
# "Foo" in project.godot AND declares `class_name Foo`. The autoload key is
# already a global identifier, so the matching class_name collides — Godot is
# expected to error "Class 'Foo' hides an autoload singleton".
class_name Foo
extends Node

func ping() -> int:
	return 1
