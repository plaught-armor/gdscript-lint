# GDScript — Style & Conventions

## Trivia

- **Dict access on known schemas** (S7, P9) — `data["key"]`, not `.get("key", default)`. `.get()` only external/optional data. Bracket `data["key"]` over Lua-style `data.key` for type-clarity (~2× perf gap, [#68834](https://github.com/godotengine/godot/issues/68834), closed 4.4 — no longer perf argument).
- **Prefer `Packed*Array` over `Array[primitive]`** (S6) — element type has packed variant (`int`/`float`/`String`/`Vector2`/`Vector3`/`Color`/byte) → use it: faster indexed access, no per-element Variant boxing. Fall back to `Array[int]`/`Array[float]` only when genuinely need Variant elements (mixed types, Object refs). Declare `var`/`static var`, never `const`; init bare literal — `var x: PackedInt32Array = [1, 2, 3]` or `= []`, never `PackedInt32Array([...])` / `PackedInt32Array()` constructor (S6b; typed annotation does conversion). On `@export` field constructor form not just redundant — reads back null in inspector, persists empty on save/reimport, silently drops authored data ([#106965](https://github.com/godotengine/godot/issues/106965)); fix = bare literal, **not** downgrade to `Array[int]`. gd-lint flags S6b only on typed assignment `: Packed*Array = Packed*Array(`, where `[]` provably converts — arg-position `foo(PackedByteArray())` left alone (there `[]` = plain `Array`). See [`engine-bugs.md`](engine-bugs.md) C1.
- **Loop shape** (H2 + L1/L2/L3 — L1/L2/L3 gd-lint **advisory**, not blocking) — (1) **type loop var** on raw ints: `for i: int in ...`, not `for i in ...` (H2, blocking — untyped iter defeats optimization). (2) **L1 — iterate directly, range only when need index**: `for x: T in coll`, not `for i in range(coll.size()): coll[i]`. **Measured ~1.3× faster** + clearer; 2-arg `range(0, coll.size())` fine (real offset). (3) **L2 — descending → `for i in range(hi, lo, -1)`, NOT manual `while` counter**. Original "descending → while" idiom **inverted by measurement**: descending `range` **~2× faster** than hand `while`. gd-lint flags numeric-countdown `while` (`while v >= N: ... v -= K`); condition-terminated `while` (not fixed count) legitimate, not matched. (4) **L3 — count loop idiom `for i: int in N`** over `range(N)`/`range(0, N)`. Style only: **measured break-even** — `range()`'s untyped-`Array` issue (C14) bites typed assignment (`var x: Array[int] = range(n)`), not `for` loop. Benchmarks + verdicts in linter's `BENCH.md`. Suppress genuine index loop with `# gdlint: ignore[L1]`.
- **No ungated `print()`** (S11) — gate behind debug flag. Synchronous I/O, measurably slow.
- **Freed-ref check** (H8) — Node may outlive: `is_instance_valid(obj)` always. Truthiness + `== null` lied on freed Nodes ([#59816](https://github.com/godotengine/godot/issues/59816), fixed **4.4** after 4.3 revert — ≤4.3 still lie). `is_instance_valid()` stays belt-and-suspenders + reads as intent on 4.4+. Resource/RefCounted: `== null` fine.
- **Non-autoload nodes must disconnect from autoload signals in `_exit_tree()`** (M5).
- **`.is_empty()`** (S15) over `== ""`, `== &""`, `.size() == 0` — works on `String`/`StringName`/`Array`/`Dictionary`/`Packed*Array`.
- **No redundant `as` after `is`** (H14) — `if x is T:` narrows; `(x as T).member` adds Variant round-trip. Only `as` when binding new var.
- **Typed-container access already typed** (H14b) — `Dictionary[K, V].get(k)` / `dict[k]` / `Array[T][i]` return typed `V` / `T`. Recasting with `as T` = same wasted round-trip as H14. `var cs: CellState = _cells.get(path)` — done. ⊥ `... as CellState`. Containers carry type; trust them.
- **Narrow a same-type Variant with `as`, not the constructor** (H14c — idiom only, perf/safety-neutral) — value already the target type but statically `Variant` (element from an untyped `Array`/`Dictionary`, `request_completed`'s `body: PackedByteArray` re-boxed through an untyped array) → prefer `x as T` over `T(x)`. Reason is **intent, not speed**: `as` reads "this *is* a `T`, narrow it"; the constructor reads "build a `T`" — a conversion that isn't happening. **Perf and safety are a wash** — measured 4.8.dev (`tests/repro_variant_narrow_cast.gd`): `Packed*Array` is copy-on-write, so both forms share the buffer with **no byte copy** (0.99×); a later mutation COW-copies for either equally (source intact both ways); and both **fail loud** on a true mismatch (`42 as PackedByteArray` → "Invalid cast"; `PackedByteArray(42)` → "Nonexistent constructor"). Don't sell it as a copy-avoidance or correctness win — it's readability. Caveat: on a genuinely *different* type `as` does a real conversion (`[1, 2, 3] as PackedByteArray` = Array → Packed), same as the ctor there — pick either. Not lintable (needs `x` static type to tell narrow from convert; blanket flag hits legit conversions — cf. S9, H10b) — reviewer's call, lowest priority. Sibling to H14/H14b: match the narrowing idiom, don't imply a conversion that isn't there. **Precedence — retype the source beats casting at all.** The Variant only exists because something upstream is untyped: the real origin is `request_completed`'s args stashed in a bare `Array`, so `response[3]` reads back as `Variant` despite `body` being a `PackedByteArray`. If you own that code, kill the cast — (1) type the handler params directly (`func _on_done(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)`) and use `body`, no `response[3]`; or (2) if you must bundle/queue the args, hold a typed `RefCounted` record, not an untyped `Array`. `x as T` (H14c) is the **fallback** — correct only when the untyped source is out of your hands (third-party API returns a bare `Array` you can't retype). Cast the Variant last, after retyping the source is off the table.
- **Shadowed params** (S3) — rename to avoid shadowing members. **Anim library prefix** — `LibName/AnimName`. **`DirAccess`** — wrap in `OS.has_feature("editor")`.
- **Null checks** (S9) — `if not x` **not** null check. Measured 4.8.dev (`tests/repro_null_checks.gd`): `not x` true for *whole* falsy set — `null`, `0`, `0.0`, `""`, `[]`, `{}`, `false`, **and `Vector2.ZERO`/`Vector3.ZERO` (zero-vectors falsy)** — while `x == null` true only for `null`. Two agree **only when `x` Object/Node ref** (null, or real object — Objects always truthy alive). Moment `x` primitive/vector where 0/empty *valid* value, `not x` latent bug:
  - `if not velocity:` fires when **stationary** (`Vector2.ZERO`). `if not damage:` fires at **0** damage. `if not name:` fires on **`""`**. `if not arr:` fires on **empty** — use `.is_empty()` for "empty", `== null` for "unset"; `not` conflates both *and* null.
  - **Rule:** primitive/vector where 0/empty meaningful → `== null` (nullable) or explicit `== 0` / `.is_empty()`, never `not x`. Object/Node ref → `if x == null:` reads as intent, dodges **H8** freed-Node truthiness history (≤4.3 `not`/`==null` lied; fixed 4.4 — `is_instance_valid()` for node may be freed). Reserve `if not x` for case where null/0/empty/false all genuinely mean "absent." Not lintable (needs `x` static type) — reviewer's call. **Perf not tiebreaker:** `== null` marginally cheaper — `not x` first materializes `x` as bool (type-dispatched truthiness cast on `Variant`) then negates, `== null` = one direct compare — but measured (`tests/repro_null_checks.gd`) gap wash-to-~1.2× on 2M iters, single-digit-ns noise-floor. Choose on correctness; speed = rounding error (cf. H1 `:=`, H4 typed signals).
- **`validate_script` MCP** after `.gd` edits — error 43 + empty errors = valid (autoload-dependent).

## Boot-validate, trust after (M10)

`@export` AND injected refs: validate once in `_ready`/`_enter_tree`, never hot paths. Own dep dies → you die with it (parent owns subtree lifecycle). Per-frame `is_instance_valid()` on own deps = wrong shape. Runtime validity check only at *external* boundaries (raycast colliders, signal payloads, dyn-instantiated targets).

```gdscript
func _ready() -> void:
    if target_path.is_empty() or target_id.is_empty():
        push_error("misconfigured")  # one-shot, designer-facing

func on_interact(_initiator: Node) -> void:
    Manager.go(target_path, target_id)  # trusted, no guard
```

### M10a — Editor-gate expensive boot validators

Two-layer boot validate:

1. **Cheap, always-on**: confirm path resolves, file parses as expected Resource type, expected fields non-null. `push_error` on miss.
2. **Expensive, editor-only**: instantiate scene, walk root fields, verify cross-refs (e.g. `pickup.item.id == slot`). Wrap in `if OS.has_feature("editor"):`. Release builds trust what editor signed off — same gate this file uses for `DirAccess`.

```gdscript
func _validate_pickup_scene(slot: Id, def: ItemDef) -> void:
    var packed: PackedScene = load(path) as PackedScene
    if packed == null:
        push_error(...); return
    if not OS.has_feature("editor"):
        return  # release: skip the instantiate-and-check cost
    var inst: Node = packed.instantiate()
    # ... root class + id checks
    inst.free()
```

Why: expensive check cost scales with asset (mesh decode, texture upload, sub-scene chains). Editor catches failure at author time + export check; release nothing new to catch, pays cost every boot.

## Push-injection > `@export NodePath` (M11)

Intra-scene sibling refs: scene-root script wires children via typed `init_*()` calls. Don't have each child declare `@export NodePath`. Wins: (1) typed params = compile-time error on misconfig; (2) no scene-path strings to rot when tree restructures; (3) co-op-safe (per-instance wiring, no `current_player` global). `NodePath` stays for **designer-overridable cross-scene** links (AI `Target`, follow camera subject).

## Deferred-boot-check (M12)

Children's `_ready` runs *before* parent's, so dep set in parent `_ready` null when child `_ready` first fires. Don't `await` (violates M1). Defer:

```gdscript
func _ready() -> void:
    set_anchors_preset(...)
    call_deferred(&"_assert_initialized")  # parent has injected by next frame

func init_hud(player: Player, rig: PlayerCameraRig, camera: Camera3D) -> void:
    _player = player; _rig = rig; _camera = camera  # typed = compile-time guarantee

func _assert_initialized() -> void:
    if _player == null or _rig == null or _camera == null:
        push_error("[reticle] init_hud not called — disabled")
        set_process(false); hide()
```

## Match arg literal to param declared type (P12a)

Bare `"x"` to `StringName` param = per-call Variant conversion. `Vector2` to `Vector2i` = silent truncate. Check `proj:class_info` / `docs <Class>.<method>` when unsure.

| Param | Right | Wrong | Where it hits |
|---|---|---|---|
| `StringName` | `&"x"` | `"x"` | `Input.is_action_*`, `InputEvent.is_action*`, `Object.call`/`call_deferred`/`has_method`/`emit_signal`/`connect`/`get`/`set`/`get_meta`/`has_meta`, `Node.add_to_group`/`is_in_group`, `AnimationPlayer.play`/`has_animation`, `Control.add_theme_*_override`, `@export var x: StringName` defaults |
| `NodePath` | `^"a/b"` | `"a/b"` | `Tween.tween_property` (property arg), `Animation` track paths |
| `String` (fs path) | `"res://..."` | `&"res://..."` | `load`, `ResourceLoader.load`, `FileAccess.open` |
| `int` | `5` | `5.0` | layer/mask bits, enum slots, `Array.resize` |
| `float` | `1.0` | `1` | `lerpf`/`clampf`/`maxf` — int forces Variant |
| `Vector2i`/`Vector3i` | `Vector2i(x,y)` | `Vector2(x,y)` | `TileMap.set_cell` — silent truncate |
| `Color` | `Color(...)` / `Color.RED` | `Vector4(...)` | typed `Color` rejects Vector4 |
| `Callable` | `Callable(o,&"m")` / `o.m` | `"m"` | `Signal.connect`, `Tween.tween_callback`, `Timer.timeout.connect` |
| `Array[T]` typed | `result.assign(filtered)` | direct assign | bug [#72566](https://github.com/godotengine/godot/issues/72566) |

`.tscn` hand-edits: `StringName` → `&"id"`, `NodePath` → `NodePath("...")`.

## `StringName`/`NodePath` ≠ `String` — same names, distinct sigs (P12b)

`StringName.begins_with(text: String)` / `.contains(what: String)` → params declared `String`, pass bare `"x"`. `StringName.substr → String`, `NodePath.get_name → StringName` → returns flip type, wrap explicitly:

```gdscript
if some_name.begins_with("Spawn_"):                       # String param, not &"x"
    var id: StringName = StringName(some_name.substr(6))  # explicit wrap on return
```

Treat each as distinct class. `docs <Class>.<method>` for actual sig.

## Type the container — no defensive Variant probing (H10b)

Control both producer + consumer of collection → declare param with full type (`Dictionary[K, V]`, `Array[T]`, `PackedStringArray`, typed `Resource` subclass). Don't take `Dictionary`/`Array`/`Variant` "for flexibility" then probe shape with `typeof()`/`is`-branching. Probing hides contract, pays Variant dispatch per access, silently accepts wrong shapes.

```gdscript
# Bad — signature lies, body probes shape per access.
static func bfs_distances(start: String, edges: Dictionary, max_depth: int) -> Dictionary:
    var neighbors: Variant = edges.get(cell, PackedStringArray())
    if typeof(neighbors) == TYPE_PACKED_STRING_ARRAY: ...
    elif neighbors is Array: ...                  # dead fallback, only test hits it

# Good — signature is the contract.
static func bfs_distances(
    start: String, edges: Dictionary[String, PackedStringArray], max_depth: int
) -> Dictionary[String, int]:
    if not edges.has(cell): continue
    var neighbors: PackedStringArray = edges[cell]
```

Boundaries (untyped justified): `JSON.parse_string` ([#97137](https://github.com/godotengine/godot/issues/97137)), `@tool` scripts, plugin/reflection, save-format-migration. Convert to typed at boundary, downstream takes typed form.

Symptoms = tighten param: untyped `Dictionary`/`Array` where every caller passes typed shape; `Variant` in non-reflection code; `typeof(x) ==` or `x is BuiltinType` branching inside body; `as` casts immediately after fetching from untyped container.

Trap: "Array or PackedStringArray" fallback almost always exercised only by test — fix test, not fn. Compat for nonexistent callers = rot.

## No duck-typed dispatch (H13)

`obj.has_method(&"foo")` + `obj.call(&"foo", ...)` zero compile-time guarantees: typo → silent no-op; `call()` returns `Variant` (missing-method `null` silently narrows to `0` on `as int`); arg types not checked. Two+ bodies sharing behavior → common base class + dispatch via `is`. Not sharing → abstraction wrong.

```gdscript
# Bad — typo, arity drift, wrong type all silently no-op.
if collider.has_method(&"on_interact"):
    collider.call(&"on_interact", self)
var leftover: int = initiator.call(&"try_pickup", item, count) as int

# Good — Interactable is the shared base.
if collider is Interactable:
    collider.on_interact(self)
var leftover: int = initiator.try_pickup(item, count)  # typed Player, direct method
```

Exception: genuine reflection (editor tools, plugins on unknown user scripts, save-system deserialization). Gameplay dispatch never that — give it base class. Same on initiator side: narrow param type over `has_method` guards.

Detection: `has_method(&"...")` + `call(&"...")` pair on same `Object` in non-`@tool` script.

## Scene inheritance for shared bodies

N scenes share root setup (script + collision_layer/mask + skeleton children) → extract base `.tscn`, use `instance=ExtResource(base)` in derived scenes. Derived scenes override only per-instance delta (data ref, mesh, collision shape). Removes per-scene boilerplate, sets clean override surface for future per-item art.

```gdscript
# scenes/items/_pickup_base.tscn — root: StaticBody3D + item_pickup.gd
# script, collision_layer=LAYER_INTERACTABLE / mask=0 (pickup is *detected*
# by the player's interact raycast, doesn't actively scan), placeholder
# MeshInstance3D + CollisionShape3D children.

# scenes/items/sword.tscn — inherits, overrides item + mesh + shape.
[gd_scene load_steps=5 format=3]
[ext_resource type="PackedScene" path="res://scenes/items/_pickup_base.tscn" id="1_base"]
[ext_resource type="Resource" path="res://resources/items/sword.tres" id="2_def"]
[sub_resource type="BoxMesh" id="..."]
[sub_resource type="BoxShape3D" id="..."]

[node name="Sword" instance=ExtResource("1_base")]
item = ExtResource("2_def")

[node name="MeshInstance3D" parent="." index="0"]
mesh = SubResource("...")

[node name="CollisionShape3D" parent="." index="1"]
shape = SubResource("...")
```

Constraints: derived scenes reference children by base's exact node names (Godot diff-merges by name + index). Don't rename base children later without sweeping derived scenes.

## Authoring-equivalence test

Runtime never re-derives stub value (e.g. designer-tuned `sword_mk2.tres` = source of truth; `UpgradeSystem.apply_part(base, part)` = authoring tool) → lock static value to computed value via GUT invariant. Test fires moment designer bumps one side without other.

Pattern preserves "ids in saves, stats in `.tres`" (no runtime-generated resources with no stable id) while keeping delta authoring honest — designers see deltas in `WeaponPartDef` but actual `.tres` hand-tunable + diffable.

```gdscript
func test_mk2_equals_base_plus_grip_part() -> void:
    var computed: WeaponDef = UpgradeSystem.apply_part(base.weapon_def, grip.part_def)
    var authored: WeaponDef = mk2.weapon_def
    for field: StringName in [&"dmg_perfect", &"sweet_spot", &"cooldown", ...]:
        assert_almost_eq(computed.get(field), authored.get(field), 0.0001, "%s drift" % field)
    assert_eq(computed.installed_features, authored.installed_features)
```

Applies any time generator + hand-authored output coexist: weapon upgrades, derived stat blocks, baked navmesh data with designer-override option. Test fails loud on drift; one place to check both sides agree.