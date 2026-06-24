extends Node

var a: Array[int] = []  # EXPECT S6
var b: Array[Vector2] = []  # EXPECT S6
var c: Array[String] = []  # EXPECT S6
var d: Array[Vector2i] = []
var e: Array[StringName] = []
var f: Array[bool] = []
var g: PackedInt32Array = PackedInt32Array([1, 2])  # EXPECT S6b
var z: PackedInt32Array = PackedInt32Array()  # EXPECT S6b
var h: PackedInt32Array = [3, 4]
var src: PackedInt32Array = [9]
var k: PackedInt32Array = PackedInt32Array(src)


func use() -> void:
	print(a, b, c, d, e, f, g, h, k, z)
	_consume(PackedByteArray())


func _consume(p: PackedByteArray) -> void:
	print(p)
