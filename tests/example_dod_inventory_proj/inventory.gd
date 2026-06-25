class_name Inventory
extends RefCounted
## Existence-based contents (D2 shape, dict variant): an item is "in the
## inventory" iff it has a count entry. Removing the last one ERASES the key —
## there is no `count == 0` zombie entry, so `distinct()` and iteration are
## naturally correct. add() respects the folded max_stack (D11/D1) and returns
## the leftover that didn't fit.

var _counts: Dictionary[int, int] = { } # Id -> count; presence == "carried"


func add(id: InvItemRegistry.Id, n: int) -> int:
	var cur: int = _counts.get(id, 0)
	var room: int = InvItemRegistry.get_def(id).max_stack - cur
	var added: int = clampi(n, 0, room)
	if added > 0:
		_counts[id] = cur + added
	return n - added # leftover that didn't fit the stack


func remove(id: InvItemRegistry.Id, n: int) -> int:
	var cur: int = _counts.get(id, 0)
	var taken: int = clampi(n, 0, cur)
	var left: int = cur - taken
	if left > 0:
		_counts[id] = left
	elif cur > 0:
		_counts.erase(id) # last one gone → drop the key (existence-based)
	return taken


func count(id: InvItemRegistry.Id) -> int:
	return _counts.get(id, 0)


func has(id: InvItemRegistry.Id) -> bool:
	return _counts.has(id)


func distinct() -> int:
	return _counts.size()
