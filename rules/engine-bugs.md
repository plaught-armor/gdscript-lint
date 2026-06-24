# GDScript — Engine Bugs

Will crash, leak, or silently corrupt. Each links to a Godot issue where one exists.

**Version status (verified 2026-06):** these are still live in current Godot — C1 (#88753), C2 (#61274, partial — packed/nested still share), C3 (#72566), C5/C7/C8 (by-design, validity-check is the prescribed pattern), C11 (#58878), C14 (#110659), C15 (#116947, dup of #88753), C16 (#87629). **Fixed in a known version** (historical below the project's min Godot): C6 (#93608, ~4.7), C10 (#76938, **4.2**), H8 freed-Node truthiness (#59816, **4.4**), H12 `@export` null (#110394, **4.6**), M9 `duplicate(true)` gap (#74918, **4.5** via `duplicate_deep()`), P9 Lua-dict perf (#68834, **4.4**). **Uncertain** — re-test on target before removing: C4 covariance (#83876, closed-completed, no fix PR linked). Keep every warning that your project's min Godot predates.

**`const` packed arrays broken** ([#88753](https://github.com/godotengine/godot/issues/88753), C1) — `const Array[PackedFloat32Array]` reports byte-count size, reads 0.0. Never `const`. Default to `var` (instance); use `static var` **only** when the table is read from outside the declaring class — a single-class private "constant" stays plain `var`, not `static var`. Literal needs no constructor wrapper — the typed annotation does the conversion: `var x: PackedInt32Array = [1, 2, 3]` (or `= []` when empty), never `PackedInt32Array([1, 2, 3])` / `PackedInt32Array()` (redundant). Flagged S6b. Holds for every `Packed*Array` (`PackedByteArray`/`PackedInt32Array`/`PackedFloat32Array`/`PackedStringArray`/`PackedVector2Array`/`PackedVector3Array`/`PackedColorArray`).

**`const` arrays/dicts are shared mutable refs** ([#61274](https://github.com/godotengine/godot/issues/61274), C2) — `const MY_ARR = [1,2,3]` mutates globally. Never mutate; `.duplicate()` first.

**Lock class-shared containers with `.make_read_only()`** (C2a) — `static var` admits the shared-mutability bug above; `.make_read_only()` enforces it. Mutations raise "Array is in read-only state"; reads work; idempotent (`.is_read_only()` to guard).

```gdscript
static var ALL: Array[ItemDef] = [null, preload("..."), ...]
func _ready() -> void:
    _validate()
    if not ALL.is_read_only(): ALL.make_read_only()
```

Limit: shallow. Nested `Array`/`Dictionary` need their own freeze. `Resource` has no freeze API (`Object.set_read_only` unimplemented) → `ALL[1].max_stack = 99` still mutates the singleton preload. At the Resource-instance layer, immutability is convention-only — code-review concern, no engine enforcement.

**Typed `.filter()`/`.map()` return untyped Array** ([#72566](https://github.com/godotengine/godot/issues/72566), C3) — must `assign()`:

```gdscript
var result: Array[BattlePawn] = []
result.assign(queue.filter(func(p): return is_instance_valid(p)))
```

**`await` on freed object leaks/crashes** ([#72629](https://github.com/godotengine/godot/issues/72629), C5) — `is_instance_valid()` after any `await` involving a node.

**RefCounted circular refs leak silently** ([#7038](https://github.com/godotengine/godot/issues/7038), C7) — `weakref()` one direction, or entity IDs (see [dod.md](dod.md) D3).

**Freed object ID reuse** ([#32383](https://github.com/godotengine/godot/issues/32383), C8) — stale ref may resolve to a different object. Null after free; check validity AND type.

**`assert()` stripped in release** (C12) — never for runtime validation. Use `if` + `push_error`.

**`sort_custom` must be strict `<`** ([#58878](https://github.com/godotengine/godot/issues/58878), C11) — never `<=`. `Array.sort()` not stable — include tiebreaker.

**Preload cycles** ([#98551](https://github.com/godotengine/godot/issues/98551), C17) — pure GDScript-script cycles fixed 4.3 (#70985), but `.tres → .tscn → .tres` resource cycles (data `.tres` references a `PackedScene` that ext_resources the same `.tres`) **still unfixed**. Carry the inverse direction as a String path or derive by convention — see [`dod.md`](dod.md) D7a + D11 and [`resource-loading.md`](resource-loading.md). Never put a `PackedScene` ext_resource on a `.tres` that a `.tscn` already ext_resources.

> Further critical-tier rules (condensed): C4 Array covariance ([#83876](https://github.com/godotengine/godot/issues/83876), closed-completed — re-test on target), C6 coroutine-after-`queue_free` ([#93608](https://github.com/godotengine/godot/issues/93608), fixed ~4.7), C10 `super()` in `_init` ([#76938](https://github.com/godotengine/godot/issues/76938), fixed 4.2), C13 `Node.new` leak, C14 `range as Array[int]` ([#110659](https://github.com/godotengine/godot/issues/110659)), C15 typed Dict + Packed* ([#116947](https://github.com/godotengine/godot/issues/116947)), C16 `static var` inheritance ([#87629](https://github.com/godotengine/godot/issues/87629)).
