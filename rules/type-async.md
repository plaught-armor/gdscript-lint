# GDScript — Type System & Async

**No `:=`** (H1) — always `var x: Type = value`. Static typing ~40-47% faster (typed instructions).

**Typed `for` loops** (H2) — `for item: Type in collection`. Untyped iter defeats optimization.

**No inline lambdas** (S1) — `gdscript-formatter` breaks indentation. Extract to named methods.

**Lambda captures by-value for locals, by-ref for members** ([#69014](https://github.com/godotengine/godot/issues/69014), H6) — share state via member vars or mutable containers.

**Concurrent coroutine race conditions** (M3) — non-deterministic resume. Use flag+poll.

**No `await` in `_ready()`** (M1) — pauses init unpredictably. `call_deferred()` or separate coroutine.

**Signal `await` without timeout** (M2) — combat/network code needs timeout fallback. See [`engine-bugs.md`](engine-bugs.md) C5 — always `is_instance_valid()` after the resume if the awaited target was a Node.

**Node method name collisions** (C9) — never shadow `get_owner`, `get_name`, `get_path`, etc.

**Typed math fns in hot paths** (P22) — `clampf`/`absf`/`maxf`/`minf`/`floorf`/`ceilf`/`roundf` for floats; `clampi`/`absi`/`maxi`/`mini` for ints. Untyped variants force Variant dispatch. Hard rule in `_process`/`_physics_process`/`_draw`.

> Further rules (condensed): H3 enum boundary, H4 signal-param types ([#110573](https://github.com/godotengine/godot/issues/110573)), H7 float→int narrowing, H9 `@onready` setter ([#71372](https://github.com/godotengine/godot/issues/71372)), H11 typed Dict + JSON ([#97137](https://github.com/godotengine/godot/issues/97137)), H12 `@export` Resource null ([#110394](https://github.com/godotengine/godot/issues/110394)), M4 mutate-during-iter, M6 temp-obj signal connection, M7 `call_deferred` end-of-frame, M8 `create_tween` node-bound, M9 `Resource.duplicate` Array skip ([#74918](https://github.com/godotengine/godot/issues/74918)).
