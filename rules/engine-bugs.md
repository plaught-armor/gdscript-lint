# GDScript — Engine Bugs

Crash, leak, or silently corrupt. Each links Godot issue where one exists.

**Version status (verified 2026-06):** still live in current Godot — C1 (#88753), C2 (#61274, partial — packed/nested still share), C3 (#72566), C5/C7 (by-design, validity-check = prescribed pattern), C11 (#58878), C14 (#72627, dup #110659), C15 (#116947, dup of #88753), C16 (#87629). **Fixed in known version** (historical below project min Godot): C6 (#93608, ~4.7), C10 (#76938, **4.2**), H8 freed-Node truthiness (#59816, **4.4**), H12 `@export` silent-null — *assigned* Resource loading null under preload/cyclic-script (#110394, fixed **4.6** by #109345); note the unassigned-`@export`-Resource null is by-design + permanent, keep the boot validator, M9 `duplicate(true)` gap (#74918, **4.5** via `duplicate_deep()`), P9 Lua-dict perf (#68834, **4.4**). **Uncertain** — re-test on target before removing: C4 covariance (#83876, closed-completed, no fix PR linked). **Retired as never-applicable to 4.x**: C8 freed-id reuse — the validator scheme makes it arithmetically impossible; see its entry below for the source read and the measurement. Keep every warning your project min Godot predates.

**`const` packed arrays broken** ([#88753](https://github.com/godotengine/godot/issues/88753), C1) — `const Array[PackedFloat32Array]` reports byte-count size, reads 0.0. Never `const`. Default `var` (instance); use `static var` **only** when table read from outside declaring class — single-class private "constant" stays plain `var`, not `static var`. Literal needs no constructor wrapper — typed annotation does conversion: `var x: PackedInt32Array = [1, 2, 3]` (or `= []` when empty), never `PackedInt32Array([1, 2, 3])` / `PackedInt32Array()`. On plain field wrapper merely redundant; on **`@export`** field = correctness/data-loss trap — constructor-from-literal form displays null in inspector ([#106965](https://github.com/godotengine/godot/issues/106965), 4.5dev4), save/reimport from null state persists empty, silently losing authored data. Fix = **not** downgrade type to `Array[int]` (costs S6 packed-array win) — drop constructor wrapper, use bare-literal init. Flagged S6b. Holds for every `Packed*Array` (`PackedByteArray`/`PackedInt32Array`/`PackedFloat32Array`/`PackedStringArray`/`PackedVector2Array`/`PackedVector3Array`/`PackedColorArray`).

**`const` arrays/dicts = shared mutable refs** ([#61274](https://github.com/godotengine/godot/issues/61274), C2) — `const MY_ARR = [1,2,3]` mutates globally. Never mutate; `.duplicate()` first.

**Lock class-shared containers with `.make_read_only()`** (C2a) — `static var` admits shared-mutability bug above; `.make_read_only()` enforces. Mutations raise "Array is in read-only state"; reads work; idempotent (`.is_read_only()` to guard).

```gdscript
static var ALL: Array[ItemDef] = [null, preload("..."), ...]
func _ready() -> void:
    _validate()
    if not ALL.is_read_only(): ALL.make_read_only()
```

Limit: shallow. Nested `Array`/`Dictionary` need own freeze. `Resource` has no freeze API (`Object.set_read_only` unimplemented) → `ALL[1].max_stack = 99` still mutates singleton preload. At Resource-instance layer, immutability convention-only — code-review concern, no engine enforcement.

**Typed `.filter()`/`.map()` return untyped Array** ([#72566](https://github.com/godotengine/godot/issues/72566), C3) — must `assign()`:

```gdscript
var result: Array[BattlePawn] = []
result.assign(queue.filter(func(p): return is_instance_valid(p)))
```

**`await` on freed object leaks/crashes** ([#72629](https://github.com/godotengine/godot/issues/72629), C5) — `is_instance_valid()` after any `await` involving node.

**RefCounted circular refs leak silently** ([#7038](https://github.com/godotengine/godot/issues/7038), C7) — `weakref()` one direction, or entity IDs (see [dod.md](dod.md) D3).

**Freed object ID reuse — DOES NOT HAPPEN IN GODOT 4** ([#32383](https://github.com/godotengine/godot/issues/32383) is a 3.x-era report, C8) — **corrected 2026-08-06, source-read + measured on 4.8.dev.** An `ObjectID` is `[1 reference bit | 39-bit validator | 24-bit slot]` (`core/object/object.h:881`). `ObjectDB::add_instance` bumps a **global monotonic** `validator_counter` on every allocation and stamps it into the slot; `ObjectDB::get_instance` compares the id's validator against the slot's and returns **nullptr** on mismatch. Reusing a whole id therefore needs the counter to wrap AND the same slot to come back: 2^39-1 ≈ 5.5e11 allocations (~6.4 days at an absurd 1M objects/sec). Measured — 200k alloc/free cycles hammering **one** slot: slot reused 200,000 times, **0 id collisions**, freed id resolves to `null`.

Consequences: `instance_from_id` on a stale id returns `null`, never a different live object. **Do not** write per-tick `weakref`, parallel-`RID`, or "right id, wrong body" guards to defend against recycling — they defend against nothing. A null check is sufficient for liveness. **The type test still earns its keep**, for the unrelated reason that an id may legitimately name a different KIND of live object than the caller wants (a `resolve()` that narrows to one class beside a `resolve_any()` that accepts several). Reference-by-ID ([dod.md](dod.md) D3) keeps every other benefit — cycle-breaking, save-friendliness, existence-based tables — and is now backed by an engine guarantee rather than working around a bug.

**`assert()` stripped in release** (C12) — never for runtime validation. Use `if` + `push_error`.

**`sort_custom` must be strict `<`** ([#58878](https://github.com/godotengine/godot/issues/58878), C11) — never `<=`. `Array.sort()` not stable — include tiebreaker.

**Resource/scene cycles** ([#80877](https://github.com/godotengine/godot/issues/80877) tracker, C17) — pure GDScript-script / `preload()`-chain cycles fixed 4.3 (#70985, PR #93346; #98551 closed as their dup), but `.tres → .tscn → .tres` resource cycles (data `.tres` references `PackedScene` that ext_resources same `.tres`) **still unfixed** — open [#109771](https://github.com/godotengine/godot/issues/109771) (4.5), silent partial-load (back-ref null) on 4.8.dev. Carry inverse direction as String path or derive by convention — see [`dod.md`](dod.md) D7a + D11 and [`resource-loading.md`](resource-loading.md). Never put `PackedScene` ext_resource on `.tres` that `.tscn` already ext_resources.

> Further critical-tier rules (condensed): C4 Array covariance ([#83876](https://github.com/godotengine/godot/issues/83876), closed-completed — re-test on target), C6 coroutine-after-`queue_free` ([#93608](https://github.com/godotengine/godot/issues/93608), fixed ~4.7), C10 `super()` in `_init` ([#76938](https://github.com/godotengine/godot/issues/76938), fixed 4.2), C13 `Node.new` leak, C14 `range as Array[int]` ([#72627](https://github.com/godotengine/godot/issues/72627), dup [#110659](https://github.com/godotengine/godot/issues/110659)), C15 typed Dict + Packed* ([#116947](https://github.com/godotengine/godot/issues/116947)), C16 `static var` inheritance ([#87629](https://github.com/godotengine/godot/issues/87629)).