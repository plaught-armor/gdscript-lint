# gdlint: disable-file
class_name ObjUtil
extends Object

## Static-only helper on a bare Object base. Never instantiated — the base class is
## the only thing under test here. Do NOT copy this shape: see the D9 note. A
## `.new()` on this leaks silently, and the base buys nothing back.

static func add(a: int, b: int) -> int:
	return a + b
