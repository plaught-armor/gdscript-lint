# gdlint: disable-file
class_name DepthBase
extends RefCounted

## Inheritance chain for the CAST_TO_SCRIPT depth probe. OPCODE_CAST_TO_SCRIPT walks
## from the instance's own script up the `while (src_type)` chain until it matches the
## target, and that walk is NOT inside #ifdef DEBUG_ENABLED. So cast cost must scale
## with the number of links walked. If it does, the walk is what the `as` row measures
## — which is the part that survives into a release build.

var v: int = 0

class D1 extends DepthBase:
	pass

class D2 extends D1:
	pass

class D3 extends D2:
	pass

class D4 extends D3:
	pass
