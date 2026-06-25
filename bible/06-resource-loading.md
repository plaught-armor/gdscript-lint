# Part VI — Resource loading

When `.tres`/`.tscn`/`Resource` load, cache, and free — and when to reach for
`preload` vs `load` vs threaded loading.

Most of the cost in a Godot project's boot path, and most of its memory
footprint, lives in the resource graph. `preload` and `load` look
interchangeable until they aren't: one freezes boot for seconds because a
`class_name`'d type pulled a sub-scene chain into the script-load phase; the
other returns null on the second frame of gameplay because someone deleted the
file under the editor. The ResourceLoader is sensible, but its defaults
silently do the right thing only if you know which default they're picking.

This part lays out the cache's actual semantics, the three loading idioms and
when each is correct, and the cache-hygiene rules learned the hard way —
including a still-unfixed cycle bug ([#98551](https://github.com/godotengine/godot/issues/98551))
that bites every project that puts a `PackedScene` ext_resource on a `.tres`.

Draws from [`../rules/resource-loading.md`](../rules/resource-loading.md).

---

## 1. Rule of thumb

> **Preload constants. Load variables. Thread-load levels.**

Three idioms, three jobs. The choice is almost mechanical once you know what
each one charges you for.

- **`preload(...)`** — small, frequently-used, statically known. UI icons,
  particle materials, item defs, weapon defs, condition tables. Cost is paid
  once, at script-load time. **Cascades through `class_name`** — preloads chain
  recursively, so heavy nested resources behind a preload can freeze boot for
  seconds. The classic blowup: a registry preloads every `WeaponDef`, each
  `WeaponDef` `@export`s a `PackedScene` for its drop pickup, each pickup
  references its mesh and shader — the script-load phase of the registry now
  pulls the entire weapon catalogue into memory before the autoload's `_ready`
  has a chance to run.
- **`load(...)`** — large, conditional, rarely touched, or anything you don't
  want pulled into boot. Pickup scenes for items the player might never drop,
  story content, dialogue trees behind unlock conditions. Spreads cost across
  gameplay rather than concentrating it at boot. Default
  `cache_mode = CACHE_MODE_REUSE`; the first call reads disk, every subsequent
  call returns the cached ref. So "load on demand" is not "load every time" —
  it is "load once, lazily."
- **`ResourceLoader.load_threaded_request(...)`** — anything whose disk + parse
  cost crosses a frame budget. Rooms, cutscenes, large bestiaries, anything
  with a long sub-resource chain. Pair with
  `load_threaded_get_status(path)` (poll across frames) →
  `load_threaded_get(path)` (retrieve when status is `THREAD_LOAD_LOADED`).

The mapping holds even on small projects. The reason to keep a strict
`preload` budget is not memory — it's boot latency: every preloaded asset
costs script-load time linearly, and `class_name` makes that cost
transitively viral.

---

## 2. Cache semantics — strong-refcount, no weak tier

ResourceLoader's cache is **strong-refcount**. There is no separate "weak
cache." A loaded resource stays in memory as long as any code holds a
reference; it frees the moment the last *external* reference drops, and the cache
entry goes with it. **4.8.dev: confirmed** (`repro_cache_proj/` → RL2) — load a
`.tres` into a local, return without keeping it, and `ResourceLoader.has_cached()`
reads `false` afterward. So the cache entry itself does **not** pin the resource:
drop every ref you hold and it's gone, no `purge()` needed.

**In plain terms:** the cache isn't a box that holds onto resources for you — it's
more like a shared address book. While *someone* in your program is holding a
loaded resource, the cache lets everyone else who asks for the same path get that
exact instance instead of re-reading the disk. The moment nobody holds it anymore,
it's freed and the cache forgets it. That's why `load()`-ing a big set-piece into a
local that goes out of scope cleans up on its own — and why stashing it in an
autoload array keeps it alive for the whole game whether you meant to or not. This
is the part that catches people:

```gdscript
class_name ItemRegistry extends RefCounted

static var ALL: Array[ItemDef] = [
    null,                                  # Id.NONE sentinel
    preload("res://resources/items/potion.tres"),
    preload("res://resources/items/sword_grip.tres"),
    # ...
]
```

`ALL` pins every `ItemDef` for the registry's lifetime — which, because it's
on a `class_name`'d global accessible from anywhere, is the entire program
run. That is usually what you want for a registry. It is emphatically not what
you want for "this dungeon's set-piece cutscene resource," which should be
loaded on entry and dropped on exit so the next dungeon doesn't inherit its
working set.

There is no `ResourceLoader.purge()` — to drop a cached resource, you drop
every reference to it. If you `load()` something into a local and the local
goes out of scope and no other code held the ref, the cache entry frees. If
anything kept it (a member var, an autoload's array, a `@export` field on a
still-living node), it stays.

### Cache modes

| Mode | Behavior |
|---|---|
| `CACHE_MODE_REUSE` (default) | Root + sub-resources pulled from cache if present. Misses load + populate. |
| `CACHE_MODE_IGNORE` | Root + direct subs bypass the cache. Dependencies still REUSE. |
| `CACHE_MODE_REPLACE` | Cached entries refreshed in place — existing refs see new data. Hot-reload flows. |
| `CACHE_MODE_IGNORE_DEEP` / `CACHE_MODE_REPLACE_DEEP` | Recursive variants. |

**4.8.dev: confirmed** (`repro_cache_proj/` → RL8) — `CACHE_MODE_REUSE` returns the
**same instance** as a plain `load()` (same `get_instance_id()`), while
`CACHE_MODE_IGNORE` returns a **fresh** instance (different id) — exactly the
table's "pulled from cache" vs "bypass the cache."

Don't pass an explicit `cache_mode` unless you have a specific reason —
`REUSE` is right almost always. Bugs
[#82830](https://github.com/godotengine/godot/issues/82830) (PackedScene cache
inconsistency) and
[#90344](https://github.com/godotengine/godot/issues/90344) hit some 4.x
versions when explicit modes are passed; re-test if you tweak.

`REPLACE` is the mode that justifies the table existing at all — it powers
hot-reload tools that swap a Resource's contents under live references. Both
`IGNORE` variants exist for narrow cases: an editor importer that needs a
fresh parse without poisoning the cache for the running game, or a debug tool
that wants to inspect a resource without taking a strong ref on it. In
gameplay code, the default is the right answer.

---

## 3. Don't roll your own cache

ResourceLoader already deduplicates by path. A
`static var SCENES: Dictionary[int, PackedScene]` populated at boot from
`load(path)` is **redundant** — every entry is also in the ResourceLoader
cache, and `load()` with `CACHE_MODE_REUSE` is the cheapest path back to that
cache. The dedicated Dict adds bookkeeping with zero behavior delta. **4.8.dev:
confirmed** (`repro_cache_proj/` → RL13) — `load(P)` called twice returns the
**same instance** (identical `get_instance_id()`), and `ResourceLoader.has_cached(P)`
is `true` after the first load: the cache *is* your dedup table.

Symptom: a registry autoload with both an `ALL: Array[ItemDef]` (the data
table) and a `SCENES: Dictionary[int, PackedScene]` (the parallel "cache").
Fold or delete the second one. The two-array shape is also the mirror-registry
anti-pattern from data-oriented design (D11 in
[`../rules/dod.md`](../rules/dod.md)) — two structures keyed by the same
discriminator that must be kept length-aligned forever, with the test suite
sprouting a parity assert to police the drift.

The fix is one of two:

1. Fold the secondary lookup into the primary record — add a `pickup_scene`
   field on `ItemDef` and let `ALL` hold it.
2. Derive at runtime via convention (D7a): `Id.SWORD_GRIP` →
   `res://scenes/items/sword_grip.tscn`. Boot validate confirms the file
   exists; the runtime lookup is one `load()`, which hits the
   ResourceLoader cache after the first call.

Either fix removes the parallel table and the parity test that guarded it.

---

## 4. Don't `ResourceLoader.exists()` after boot validate

Boot validate already errors on missing paths. After boot, the only way
`load()` can return null is asset deletion mid-runtime — at which point a
redundant `exists()` guard gives the caller the same null they'd get from
`load()` directly, just one hash lookup cheaper. Trust the boot pass:

```gdscript
# Bad — exists() is dead weight after _validate ran at autoload boot.
func get_pickup_scene(id: Id) -> PackedScene:
    if not ResourceLoader.exists(path): return null
    return load(path) as PackedScene

# Good — caller handles null from load() the same way.
func get_pickup_scene(id: Id) -> PackedScene:
    return load(path) as PackedScene
```

`exists()` still earns its keep **inside** boot validate (catches missing
files at boot rather than first use) — drop it only on the runtime-lookup hot
path. The principle is M10's *boot-validate, trust after*: the place to check
shape is once at boundary, then every callsite downstream trusts it. Putting
`exists()` on the runtime path is the same shape error as
`is_instance_valid()` on an own dep in `_physics_process` — a guard placed at
the wrong layer.

---

## 5. Editor-gate expensive validators

When boot validate instantiates scenes or walks resources (mesh decode,
texture upload, sub-scene chains), wrap the expensive layer in
`if OS.has_feature("editor"):`. Release builds trust what the editor signed
off; they have nothing new to catch and pay the cost on every boot.

The pattern is two-layer:

1. **Cheap, always-on.** Confirm path resolves, file parses as the expected
   Resource type, expected fields are non-null. `push_error` on miss.
2. **Expensive, editor-only.** Instantiate the scene, walk root fields, verify
   cross-refs (e.g. `pickup.item.id == slot`). Wrap in
   `if OS.has_feature("editor"):`.

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

The cost of the expensive check scales with the asset: mesh decode, texture
upload, sub-scene chain traversal. The editor build catches the failure at
author time and at export-check; the release build has nothing new to discover
the first time the player loads in. Full pattern lives at
[`../rules/style.md`](../rules/style.md) M10a; the resource-loading angle is
just that *this* is the layer where the cost lives, so this is the layer to
gate.

---

## 6. No bidirectional `.tres ↔ .tscn` ext_resource

Engine bug C17 ([#98551](https://github.com/godotengine/godot/issues/98551))
— preload cycles can hang or load partial Resources. Pure GDScript-script
cycles were fixed in 4.3 (#70985), but `.tres → .tscn → .tres` resource
cycles **remain unfixed** at time of writing. The cycle most often forms like
this:

- A `.tscn` ext_resources its data `.tres` (normal — a pickup scene
  references the `ItemDef` that describes it).
- The `.tres` adds an `@export var pickup_scene: PackedScene` pointing back at
  the `.tscn` "for convenience" (so gameplay code can do
  `def.pickup_scene.instantiate()` without a separate lookup).
- The engine resolves `.tres → .tscn → .tres → .tscn → ...`.

Symptoms: editor freeze on open, partially-populated Resources at runtime
(`def.pickup_scene` is null even though the `.tres` clearly says otherwise),
nondeterministic load order — the cycle resolves whichever side loses the race
on the parse.

Fix: carry the inverse direction as a **String path** (or, better, derive it
by **convention** from a stable key — see [`../rules/dod.md`](../rules/dod.md)
D7a convention-derived dispatch). The `.tres` stays a leaf in the dependency
graph; the `.tscn` keeps its forward ref. The `.tscn → .tres` direction is
the natural one — pickup scene knows its def — and the inverse lookup
(`def → scene`) is rare enough to derive lazily:

```gdscript
# Bad — @export PackedScene on the .tres closes the cycle.
class_name ItemDef extends Resource
@export var id: ItemRegistry.Id
@export var pickup_scene: PackedScene   # ext_resources the .tscn → cycle

# Good — convention. The .tres carries the id; the scene path is derived.
class_name ItemDef extends Resource
@export var id: ItemRegistry.Id
# pickup scene resolved on demand:
#   "res://scenes/items/%s.tscn" % _basename(id)
```

Boot validate (Part 5 above) calls `_basename(id)` for every slot, confirms
the corresponding file exists, and crashes loud if not — so the missing-arm
case surfaces at boot, not at first use. The runtime lookup is one `load()`
against the ResourceLoader cache.

The general rule: a `.tres` is a **leaf** in the dependency graph. It can be
referenced; it should not reference back. `.tscn`'s and code reach into
`.tres`'s, never the other way around.

---

## 7. UID files (`.uid` sidecars) — commit them

Every imported resource has a UID; `.tscn` and `.tres` store theirs in the
header. Godot 4.4+ adds `.uid` sidecar files so scripts and shaders
participate too — formats that previously had no place to put a UID now carry
one in a separate file next to the source.

`ext_resource` lines look like:

```
[ext_resource type="..." uid="uid://..." path="res://..." id="..."]
```

The UID is the resolution key; the path is the editor-display fallback for
when the UID can't resolve. This means:

- **Commit `.uid` files to git.** Without them, cloning the project breaks
  every ext_resource reference on the new host — the UIDs the scenes recorded
  no longer resolve to any file in the project. A common `.gitignore` mistake
  is to ignore `*.uid` along with build artifacts; do not.
- **Renaming or moving a file with its `.uid` keeps references valid.** The
  scene that references it looks up by UID, finds the moved file at its new
  path, and works.
- **Renaming without `.uid` silently breaks references.** No error at editor
  start; the broken refs surface as null fields the first time gameplay touches
  them.

This is also the mechanism that makes script and shader refactors safe: rename
`scripts/data/item_def.gd` to `scripts/data/items/def.gd` with its `.uid` and
every `.tres` that references it still resolves. Without the sidecar, the
move silently snaps every link.

---

## 8. Miscellaneous

A handful of smaller rules that don't justify a section each:

- **`Resource.duplicate()`** makes a shallow copy. **4.8.dev: confirmed**
  (`repro_cache_proj/` → RL22) — after `var dup = orig.duplicate()`, appending to
  `dup.tags` also changed `orig.tags`: the nested `Array` is the *same* object in
  both. **In plain terms:** a shallow copy duplicates the box but not what's inside
  it — top-level fields are copied, but a nested `Array`/`Dictionary`/sub-`Resource`
  is shared between the original and the copy, so mutating it through one is visible
  through the other. Use `duplicate()` when you want a per-instance variant of a
  shared design-time Resource — e.g. per-door reinforcement HP that starts from the
  `DoorDef` defaults but mutates over the playthrough — and reach for deep
  duplication (its own footgun, M9 in
  [`../rules/type-async.md`](../rules/type-async.md)) only when the nested contents
  must be independent too.
- **`make_read_only()`** on `Array` / `Dictionary` after boot validate locks
  the structure against accidental mutation. Pairs with `static var` — see
  [`../rules/engine-bugs.md`](../rules/engine-bugs.md) C2a. Shallow only:
  nested `Array`/`Dictionary` need their own freeze, and `Resource` instances
  inside the array do not freeze (no engine-level read-only on Resources at
  time of writing).
- **`ResourceLoader.has_cached(path)`** is a free check — use it when you
  want to *decide* between a sync `load()` and a threaded prewarm, not when
  you already know you'll call `load()` regardless. As a guard before
  `load()`, it's the same shape error as the `exists()` antipattern in §4.
- **Don't `await ResourceLoader.load_threaded_request(...)`** — it's not a
  coroutine. The threaded API is poll-based: request, poll status, get when
  loaded. `await`-ing it returns null and corrupts your async flow.
  [`../rules/type-async.md`](../rules/type-async.md) covers signal and
  `await` traps in detail.

---

## The shape of a healthy resource graph

If you take three things from this part:

1. **`preload` charges at script-load time and cascades through `class_name`.**
   Keep the preload budget for things that genuinely belong in boot —
   registries, UI icons, condition tables. Everything else is `load` on
   demand, which hits the same cache after the first call.
2. **The ResourceLoader cache is strong-refcount with no weak tier.** A
   resource lives exactly as long as the longest-lived reference to it. To
   drop one, drop every ref; do not look for a `purge()` API — there isn't
   one.
3. **`.tres` is a leaf in the dependency graph.** `.tscn` references `.tres`;
   code references `.tres`; `.tres` does not reference back to `.tscn`. The
   `.tres → .tscn → .tres` cycle bug
   ([#98551](https://github.com/godotengine/godot/issues/98551)) is still
   unfixed, and the convention-derived dispatch in D7a is how you avoid it.

The defaults are right almost always. The two places to be careful are the
boundary between `preload` and `load` (because `class_name` makes preloads
viral) and the direction of references between `.tres` and `.tscn` (because
the cycle bug is silent until it isn't).

## Sources

- [Godot 4 — Resources (tutorial)](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Logic preferences (best practices)](https://docs.godotengine.org/en/stable/tutorials/best_practices/logic_preferences.html)
- [Do Not Use Preload — theduriel](https://theduriel.github.io/Godot/Do-not-use---Preload)
- [UID changes coming to Godot 4.4 — official blog](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)
