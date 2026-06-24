extends Node


func loops(coll: Array) -> void:
	for i: int in range(coll.size()):  # EXPECT L1
		print(coll[i])
	for j: int in range(1, coll.size()):
		print(j)
	for x: int in range(10, 0, -1):
		print(x)
	for z: int in range(0, 10, 2):
		print(z)
	for k: int in range(8):  # EXPECT L3
		print(k)
	for n: int in range(0, 8):  # EXPECT L3
		print(n)


func descending() -> void:
	var w: int = 10
	while w > 0:  # EXPECT L2
		print(w)
		w -= 1
