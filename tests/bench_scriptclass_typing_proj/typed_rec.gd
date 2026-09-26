# gdlint: disable-file
class_name TypedRec
extends RefCounted

## Plain record under test: does declaring a var/param as this script class buy the
## same speedup that declaring one as `int` does? Fields only + one method, matching
## the D1/D6 record shape.

var v: int = 0


func bump(a: int) -> int:
	return a + 1
