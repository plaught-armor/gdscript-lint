---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/project.godot"
---

# GDScript — Type System & Async

**No `:=`** (H1) — always `var x: Type = value`. `:=` also typed (perf wash, §03 measured) → ban = consistency/readability, not speed. Static typing vs untyped `var x =` ~25-47% faster (workload-dep; ~1.35× typical 4.8.dev).

**Typed `for` loops** (H2) — `for item: Type in collection`. Untyped iter defeats optimization.

**Member initializers run in DECLARATION ORDER; a forward reference reads the type zero** (H15) — a
`var`/`static var` initializer that reads a member declared **below** it gets that field's zero value
(`0`, `0.0`, `null`, empty `Array`), not its eventual value. **Silent** — no warning, no error, and
the field ends up holding a plausible wrong number. Measured 4.8.dev
(`tests/repro_member_init_order.gd`): `var a: int = b + 1` above `var b: int = 42` yields `a == 1`;
below it, `a == 43`. Same for `static var`. Same inside an inner class. `_init`'s body runs after
every initializer, so it sees real values.

```gdscript
# Bad — reads 0, ships 1, nothing complains.
var _end_frame: int = _out_frame + 60
var _out_frame: int = int(SECONDS * 60.0)

# Good — declare the source first, or derive both from the const.
var _out_frame: int = int(SECONDS * 60.0)
var _end_frame: int = _out_frame + 60
```

`const` is the exception and the fix: consts are **constant-folded**, so a `const` may reference one
declared below it and still read the real value, and a `var` initializer reading a `const` is always
safe regardless of order. Bites hardest where one member is *derived* from another — a test
harness's frame schedule off a duration dial, a cached bound off a size — which is exactly where the
symptom is a wrong measurement rather than a crash. Assign in `_ready`/`_init` if declaration order
can't be arranged.

**Lambda captures by-value for locals, by-ref for members** ([#69014](https://github.com/godotengine/godot/issues/69014), H6) — share state via member vars or mutable containers.

**Concurrent coroutine race conditions** (M3) — non-deterministic resume. Use flag+poll.

**No `await` in `_ready()`** (M1) — pauses init unpredictably. `call_deferred()` or separate coroutine.

**Signal `await` without timeout** (M2) — combat/network code needs timeout fallback. See [`engine-bugs.md`](engine-bugs.md) C5 — always `is_instance_valid()` after resume if awaited target Node.

**Node method name collisions** (C9) — never shadow `get_owner`, `get_name`, `get_path`, etc.

**Typed math fns in hot paths** (P22) — `clampf`/`absf`/`maxf`/`minf`/`floorf`/`ceilf`/`roundf` floats; `clampi`/`absi`/`maxi`/`mini` ints. Untyped variants force Variant dispatch. Hard rule in `_process`/`_physics_process`/`_draw`.

> Further rules (condensed): H3 enum boundary, H4 signal-param types ([#110573](https://github.com/godotengine/godot/issues/110573)), H7 float→int narrowing, H9 `@onready` setter ([#71372](https://github.com/godotengine/godot/issues/71372)), H11 typed Dict + JSON ([#97137](https://github.com/godotengine/godot/issues/97137)), H12 `@export` Resource null — unassigned = null by-design (permanent, boot-validate); separately [#110394](https://github.com/godotengine/godot/issues/110394) silent-null of an *assigned* one under preload/cyclic-script fixed 4.6 ([#109345](https://github.com/godotengine/godot/pull/109345)), M4 mutate-during-iter, M6 temp-obj signal connection, M7 `call_deferred` end-of-frame, M8 `create_tween` node-bound, M9 `Resource.duplicate` Array skip ([#74918](https://github.com/godotengine/godot/issues/74918)).