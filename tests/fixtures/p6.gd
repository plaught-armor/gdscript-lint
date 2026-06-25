extends Node

# Untyped Array on purpose: a typed Array[int] would also trip S6, muddying the
# P6 assertion. pop_front/pop_at exist only on Array, so this is the real target.
var queue: Array = [1, 2, 3]


func drain() -> void:
	var head: int = queue.pop_front() # EXPECT P6
	var also: int = queue.pop_at(0) # EXPECT P6
	print(head, also)


func ok() -> void:
	# pop_back is O(1) — not flagged.
	var tail: int = queue.pop_back()
	# pop_at with a non-front index is a real mid-removal, not the front-shift smell.
	var mid: int = queue.pop_at(2)
	# the literal 'pop_front(' inside a string must not trip the masker.
	var note: String = "call pop_front() to dequeue"
	print(tail, mid, note)
