extends Node

var items: Array = []


func _double(x: int) -> int:
	return x * 2


func _is_hostile(p: Node) -> bool:
	return p != null


func _cmp(a: int, b: int) -> bool:
	return a < b


func bad() -> void:
	# Pure pass-through: lambda forwards its params verbatim to a named fn.
	# Pass the reference instead — wrapping double-dispatches.
	items.map(func(x): return _double(x)) # EXPECT P19
	items.filter(func(p): return _is_hostile(p)) # EXPECT P19
	var cb: Callable = func(x): return _double(x) # EXPECT P19
	# dotted callee — pass `self._double` / the method ref.
	items.map(func(x): return self._double(x)) # EXPECT P19


func ok() -> void:
	# Reference passed directly — the fix; nothing to flag.
	items.map(_double)
	items.filter(_is_hostile)
	# Real inline body (not a wrapped named call).
	items.map(func(x): return x * 2)
	# Partial application — extra constant arg; a reference can't express it.
	items.map(func(x): return _cmp(x, 5))
	# Reordered args — a reference can't reorder; not a pass-through.
	items.sort_custom(func(a, b): return _cmp(b, a))
	# Body calls a method ON the param — callee root is the param itself.
	items.filter(func(p): return p.is_alive())
	# Zero-arg thunk — deferral is often the point; left alone.
	var t: Callable = func(): return _double(3)
