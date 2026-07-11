# GDScript — Resource Loading

How `.tres` / `.tscn` / `Resource` load, cache, free in Godot 4. When `preload` vs `load` vs `load_threaded_request`. Cache hygiene rules learned hard way.

## Rule of thumb

> **Preload constants. Load variables. Thread-load levels.**

- **`preload(...)`** — small, frequent, statically known. UI icons, particle materials, item defs, weapon defs, condition tables. Cost paid once at script-load. **Cascades through `class_name`** — preloads chain recursively → heavy nested resources behind preload can freeze boot seconds.
- **`load(...)`** — large, conditional, rarely touched, or anything you don't want in boot. Pickup scenes for items player might never drop, story content. Spreads cost across gameplay. Default `cache_mode = CACHE_MODE_REUSE`; first call reads disk, rest return cached ref.
- **`ResourceLoader.load_threaded_request(...)`** — anything whose disk + parse cost crosses frame budget. Rooms, cutscenes, large bestiaries. Pair with `load_threaded_get_status(path)` (poll across frames) → `load_threaded_get(path)` (retrieve).

## Cache semantics

ResourceLoader cache = **strong-refcount**. No separate "weak cache." Loaded resource stays in memory while any code holds ref (cache itself counts); frees moment last ref drops. `static var ALL: Array[ItemDef] = [preload(...), ...]` pins everything in array for autoload's lifetime — forever in practice.

### Cache modes

| Mode | Behavior |
|---|---|
| `CACHE_MODE_REUSE` (default) | Root + sub-resources pulled from cache if present. Misses load + populate. |
| `CACHE_MODE_IGNORE` | Root + direct subs bypass cache. Dependencies still REUSE. |
| `CACHE_MODE_REPLACE` | Cached entries refreshed in place — existing refs see new data. Hot-reload flows. |
| `CACHE_MODE_IGNORE_DEEP` / `CACHE_MODE_REPLACE_DEEP` | Recursive variants. |

⊥ pass explicit cache_mode without specific reason — `REUSE` right almost always. Bugs [#82830](https://github.com/godotengine/godot/issues/82830) (PackedScene cache inconsistency) & [#90344](https://github.com/godotengine/godot/issues/90344) hit some 4.x versions when explicit modes passed; re-test if you tweak.

## Don't roll your own cache

ResourceLoader already dedupes by path. `static var SCENES: Dictionary[int, PackedScene]` populated at boot from `load(path)` = **redundant** — every entry also in ResourceLoader cache, & `load()` with `CACHE_MODE_REUSE` = cheapest path back to it. Dedicated Dict adds bookkeeping, zero behavior delta.

Symptom: registry autoload with both `ALL: Array[ItemDef]` (data table) & `SCENES: Dictionary[int, PackedScene]` (parallel "cache"). Fold or delete second.

## Don't `ResourceLoader.exists()` after boot validate

Boot validate already errors on missing paths. After boot, only way `load()` returns null = asset deleted mid-runtime — at which point redundant `exists()` guard gives caller same null they'd get from `load()` directly, one hash lookup cheaper. Trust boot pass:

```gdscript
# Bad — exists() is dead weight after _validate ran at autoload boot.
func get_pickup_scene(id: Id) -> PackedScene:
    if not ResourceLoader.exists(path): return null
    return load(path) as PackedScene

# Good — caller handles null from load() the same way.
func get_pickup_scene(id: Id) -> PackedScene:
    return load(path) as PackedScene
```

`exists()` still earns keep **inside** boot validate (catches missing files at boot not first use) — drop only on runtime-lookup hot path.

## Editor-gate expensive validators

When boot validate instantiates scenes / walks resources (mesh decode, texture upload, sub-scene chains), wrap expensive layer in `if OS.has_feature("editor"):`. Release trusts what editor signed off. Full pattern + example: [`style.md`](style.md) M10a.

## No bidirectional `.tres ↔ .tscn` ext_resource

Engine bug C17 ([#98551](https://github.com/godotengine/godot/issues/98551)) — preload cycles can hang or load partial Resources. Cycles most often form as `.tres → .tscn → .tres`:

- `.tscn` ext_resources its data `.tres` (normal — pickup scene references ItemDef).
- `.tres` adds `@export var pickup_scene: PackedScene` pointing back at `.tscn`.
- Engine resolves `.tres → .tscn → .tres → ...`.

Fix: carry inverse direction as **String path** (or better, derive by **convention** from stable key — see [`dod.md`](dod.md) D7a convention-derived dispatch). `.tres` stays leaf in dependency graph; `.tscn` keeps forward ref. See [`engine-bugs.md`](engine-bugs.md) C17 for bug itself.

## UID files (`.uid` sidecars)

- Every imported resource has UID; `.tscn` / `.tres` store it in header. Godot 4.4+ adds `.uid` sidecar files so scripts & shaders participate too.
- `[ext_resource type="..." uid="uid://..." path="res://..." id="..."]` — UID = resolution key, path = editor-display fallback.
- **Commit `.uid` files to git**. Without them, cloning project breaks every ext_resource reference on new host.
- Renaming/moving file with its `.uid` keeps references valid. Renaming without `.uid` silently breaks them.

## Misc

- `Resource.duplicate()` makes shallow copy. Use when you need per-instance mutable variant of shared design-time Resource (e.g. per-door reinforcement HP state).
- `make_read_only()` on `Array` / `Dictionary` after boot validate locks structure against accidental mutation. Pairs with `static var` — see [`engine-bugs.md`](engine-bugs.md) C2a.
- `ResourceLoader.has_cached(path)` = free check — use when you want to *decide* between sync `load()` & threaded prewarm, not when you already know you'll call `load()` regardless.
- ⊥ `await ResourceLoader.load_threaded_request(...)` — not coroutine. Poll status instead. [`type-async.md`](type-async.md) covers signal/await traps.

## Sources

- [Godot 4 — Resources (tutorial)](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Logic preferences (best practices)](https://docs.godotengine.org/en/stable/tutorials/best_practices/logic_preferences.html)
- [Do Not Use Preload — theduriel](https://theduriel.github.io/Godot/Do-not-use---Preload)
- [UID changes coming to Godot 4.4 — official blog](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)