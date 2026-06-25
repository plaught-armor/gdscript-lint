# GDScript — Style & Conventions

## Trivia

- **Dict access on known schemas** (S7, P9) — `data["key"]`, not `.get("key", default)`. `.get()` only for external/optional data. Use bracket `data["key"]` over Lua-style `data.key` for type-clarity (the ~2× perf gap, [#68834](https://github.com/godotengine/godot/issues/68834), closed 4.4 — no longer a perf argument).
- **Prefer `Packed*Array` over `Array[primitive]`** (S6) — when the element type has a packed variant (`int`/`float`/`String`/`Vector2`/`Vector3`/`Color`/byte), use it: faster indexed access, no per-element Variant boxing. Fall back to `Array[int]`/`Array[float]` only when you genuinely need Variant elements (mixed types, Object refs). Declare `var`/`static var`, never `const`; init with a bare literal — `var x: PackedInt32Array = [1, 2, 3]` or `= []`, never the `PackedInt32Array([...])` / `PackedInt32Array()` constructor (S6b; the typed annotation does the conversion). gd-lint flags S6b only on a typed assignment `: Packed*Array = Packed*Array(`, where the `[]` provably converts — arg-position `foo(PackedByteArray())` is left alone (there `[]` would be a plain `Array`). See [`engine-bugs.md`](engine-bugs.md) C1.
- **Loop shape** (H2 + L1/L2/L3 — L1/L2/L3 are gd-lint **advisory**, not blocking) — (1) **type the loop var** on raw ints: `for i: int in ...`, not `for i in ...` (H2, blocking — untyped iter defeats optimization). (2) **L1 — iterate directly, range only when you need the index**: `for x: T in coll`, not `for i in range(coll.size()): coll[i]`. **Measured ~1.3× faster** + clearer; a 2-arg `range(0, coll.size())` is fine (real offset). (3) **L2 — descending → `for i in range(hi, lo, -1)`, NOT a manual `while` counter**. The original "descending → while" idiom was **inverted by measurement**: a descending `range` is **~2× faster** than the hand `while`. gd-lint flags a numeric-countdown `while` (`while v >= N: ... v -= K`); a condition-terminated `while` (not a fixed count) is legitimate and not matched. (4) **L3 — count loop idiom `for i: int in N`** over `range(N)`/`range(0, N)`. Style only: **measured break-even** — `range()`'s untyped-`Array` issue (C14) bites typed assignment (`var x: Array[int] = range(n)`), not a `for` loop. Benchmarks + verdicts recorded in the linter's `BENCH.md`. Suppress a genuine index loop with `# gdlint: ignore[L1]`.
- **No ungated `print()`** (S11) — gate behind debug flag. Synchronous I/O, measurably slow.
- **Freed-ref check** (H8) — Node may outlive: `is_instance_valid(obj)` always. Truthiness + `== null` lied on freed Nodes ([#59816](https://github.com/godotengine/godot/issues/59816), fixed **4.4** after a 4.3 revert — ≤4.3 still lie). `is_instance_valid()` stays belt-and-suspenders + reads as intent on 4.4+. Resource/RefCounted: `== null` fine.
- **Non-autoload nodes must disconnect from autoload signals in `_exit_tree()`** (M5).
- **`.is_empty()`** (S15) over `== ""`, `== &""`, `.size() == 0` — works on `String`/`StringName`/`Array`/`Dictionary`/`Packed*Array`.
- **No redundant `as` after `is`** (H14) — `if x is T:` narrows; `(x as T).member` adds Variant round-trip. Only `as` when binding to new var.
- **Typed-container access is already typed** (H14b) — `Dictionary[K, V].get(k)` / `dict[k]` / `Array[T][i]` return typed `V` / `T`. Recasting with `as T` is the same wasted round-trip as H14. `var cs: CellState = _cells.get(path)` — done. ⊥ `... as CellState`. Containers carry their type; trust them.
- **Shadowed params** (S3) — rename to avoid shadowing members. **Anim library prefix** — `LibName/AnimName`. **`DirAccess`** — wrap in `OS.has_feature("editor")`.
- **Null checks** (S9) — `if not x` is **not** a null check. Measured 4.8.dev (`tests/repro_null_checks.gd`): `not x` is true for the *whole* falsy set — `null`, `0`, `0.0`, `""`, `[]`, `{}`, `false`, **and `Vector2.ZERO`/`Vector3.ZERO` (zero-vectors are falsy)** — while `x == null` is true only for `null`. So the two agree **only when `x` is an Object/Node ref** (null, or a real object — Objects are always truthy alive). The moment `x` is a primitive/vector where 0/empty is a *valid* value, `not x` is a latent bug:
  - `if not velocity:` fires when **stationary** (`Vector2.ZERO`). `if not damage:` fires at **0** damage. `if not name:` fires on **`""`**. `if not arr:` fires on **empty** — use `.is_empty()` for "empty", `== null` for "unset"; `not` conflates both *and* null.
  - **Rule:** primitive/vector where 0/empty is meaningful → `== null` (nullable) or explicit `== 0` / `.is_empty()`, never `not x`. Object/Node ref → `if x == null:` reads as intent and dodges the **H8** freed-Node truthiness history (≤4.3 `not`/`==null` lied; fixed 4.4 — `is_instance_valid()` for a node that may be freed). Reserve `if not x` for the case where null/0/empty/false all genuinely mean "absent." Not lintable (needs `x`'s static type) — reviewer's call. **Perf is not the tiebreaker:** `== null` is marginally cheaper — `not x` first materializes `x` as a bool (a type-dispatched truthiness cast on a `Variant`) then negates, while `== null` is one direct compare — but measured (`tests/repro_null_checks.gd`) the gap is a wash-to-~1.2× on 2M iters, i.e. single-digit-ns noise-floor. Choose on correctness; the speed is a rounding error (cf. H1 `:=`, H4 typed signals).
- **`validate_script` MCP** after `.gd` edits — error 43 + empty errors = valid (autoload-dependent).

## Boot-validate, trust after (M10)

`@export` AND injected refs: validate once in `_ready`/`_enter_tree`, never in hot paths. If your own dep dies, you die with it (parent owns subtree lifecycle). Per-frame `is_instance_valid()` on own deps = wrong shape. Runtime validity check only belongs at *external* boundaries (raycast colliders, signal payloads, dyn-instantiated targets).

```gdscript
func _ready() -> void:
    if target_path.is_empty() or target_id.is_empty():
        push_error("misconfigured")  # one-shot, designer-facing

func on_interact(_initiator: Node) -> void:
    Manager.go(target_path, target_id)  # trusted, no guard
```

### M10a — Editor-gate expensive boot validators

Two-layer boot validate:

1. **Cheap, always-on**: confirm path resolves, file parses as the expected Resource type, expected fields are non-null. `push_error` on miss.
2. **Expensive, editor-only**: instantiate the scene, walk root fields, verify cross-refs (e.g. `pickup.item.id == slot`). Wrap in `if OS.has_feature("editor"):`. Release builds trust what the editor signed off — same gate this file uses for `DirAccess`.

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

Why: the expensive check's cost scales with the asset (mesh decode, texture upload, sub-scene chains). Editor catches the failure at author time + export check; release has nothing new to catch and pays the cost on every boot.

## Push-injection > `@export NodePath` (M11)

Intra-scene sibling refs: scene-root script wires children via typed `init_*()` calls. Don't have each child declare `@export NodePath`. Wins: (1) typed params = compile-time error on misconfig; (2) no scene-path strings to rot when tree restructures; (3) co-op-safe (per-instance wiring, no `current_player` global). `NodePath` stays for **designer-overridable cross-scene** links (AI `Target`, follow camera subject).

## Deferred-boot-check (M12)

Children's `_ready` runs *before* parent's, so a dep set in parent `_ready` is null when child's `_ready` first fires. Don't `await` (violates M1). Defer:

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

When you control both producer + consumer of a collection, declare the parameter with its full type (`Dictionary[K, V]`, `Array[T]`, `PackedStringArray`, typed `Resource` subclass). Don't take `Dictionary`/`Array`/`Variant` "for flexibility" then probe shape with `typeof()`/`is`-branching. Probing hides the contract, pays Variant dispatch per access, silently accepts wrong shapes.

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

Symptoms = tighten the param: untyped `Dictionary`/`Array` where every caller passes a typed shape; `Variant` in non-reflection code; `typeof(x) ==` or `x is BuiltinType` branching inside body; `as` casts immediately after fetching from an untyped container.

Trap: the "Array or PackedStringArray" fallback is almost always exercised only by a test — fix the test, not the fn. Compat for nonexistent callers is rot.

## No duck-typed dispatch (H13)

`obj.has_method(&"foo")` + `obj.call(&"foo", ...)` has zero compile-time guarantees: typo → silent no-op; `call()` returns `Variant` (missing-method `null` silently narrows to `0` on `as int`); arg types not checked. Two+ bodies sharing behavior → common base class + dispatch via `is`. Not sharing → abstraction is wrong.

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

Exception: genuine reflection (editor tools, plugins on unknown user scripts, save-system deserialization). Gameplay dispatch is never that — give it a base class. Same on initiator side: narrow the parameter type over `has_method` guards.

Detection: `has_method(&"...")` + `call(&"...")` pair on same `Object` in non-`@tool` script.

## Scene inheritance for shared bodies

When N scenes share root setup (script + collision_layer/mask + skeleton children), extract a base `.tscn` and use `instance=ExtResource(base)` in the derived scenes. Derived scenes override only the per-instance delta (the data ref, the mesh, the collision shape). Removes per-scene boilerplate, sets up a clean override surface for future per-item art.

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

Constraints: derived scenes reference children by the base's exact node names (Godot diff-merges by name + index). Don't rename base children later without sweeping derived scenes.

## Authoring-equivalence test

When a runtime never re-derives a stub value (e.g. designer-tuned `sword_mk2.tres` is the source of truth; `UpgradeSystem.apply_part(base, part)` is the authoring tool), lock the static value to the computed value via a GUT invariant. The test fires the moment a designer bumps one side without the other.

Pattern preserves "ids in saves, stats in `.tres`" (no runtime-generated resources with no stable id) while keeping the delta authoring honest — designers see the deltas in `WeaponPartDef` but the actual `.tres` is hand-tunable + diffable.

```gdscript
func test_mk2_equals_base_plus_grip_part() -> void:
    var computed: WeaponDef = UpgradeSystem.apply_part(base.weapon_def, grip.part_def)
    var authored: WeaponDef = mk2.weapon_def
    for field: StringName in [&"dmg_perfect", &"sweet_spot", &"cooldown", ...]:
        assert_almost_eq(computed.get(field), authored.get(field), 0.0001, "%s drift" % field)
    assert_eq(computed.installed_features, authored.installed_features)
```

Applies any time a generator + a hand-authored output coexist: weapon upgrades, derived stat blocks, baked navmesh data with a designer-override option. Test fails loud on drift; one place to check both sides agree.
