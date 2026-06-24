# GDScript — Resource Loading

How `.tres` / `.tscn` / `Resource` load, cache, and free in Godot 4. When to reach for `preload` vs `load` vs `load_threaded_request`. Cache hygiene rules learned the hard way.

## Rule of thumb

> **Preload constants. Load variables. Thread-load levels.**

- **`preload(...)`** — small, frequently-used, statically known. UI icons, particle materials, item defs, weapon defs, condition tables. Cost is paid once at script-load time. **Cascades through `class_name`** — preloads chain recursively, so heavy nested resources behind preload can freeze boot for seconds.
- **`load(...)`** — large, conditional, rarely touched, or anything you don't want pulled into boot. Pickup scenes for items the player might never drop, story content. Spreads cost across gameplay. Default `cache_mode = CACHE_MODE_REUSE`; first call reads disk, all subsequent calls return the cached ref.
- **`ResourceLoader.load_threaded_request(...)`** — anything whose disk + parse cost crosses a frame budget. Rooms, cutscenes, large bestiaries. Pair with `load_threaded_get_status(path)` (poll across frames) → `load_threaded_get(path)` (retrieve).

## Cache semantics

ResourceLoader's cache is **strong-refcount**. There's no separate "weak cache." A loaded resource stays in memory as long as any code holds a ref (the cache itself counts as one); it frees the moment the last ref drops. `static var ALL: Array[ItemDef] = [preload(...), ...]` pins everything in that array for the autoload's lifetime — i.e. forever in practice.

### Cache modes

| Mode | Behavior |
|---|---|
| `CACHE_MODE_REUSE` (default) | Root + sub-resources pulled from cache if present. Misses load + populate. |
| `CACHE_MODE_IGNORE` | Root + direct subs bypass the cache. Dependencies still REUSE. |
| `CACHE_MODE_REPLACE` | Cached entries refreshed in place — existing refs see new data. Hot-reload flows. |
| `CACHE_MODE_IGNORE_DEEP` / `CACHE_MODE_REPLACE_DEEP` | Recursive variants. |

Don't pass an explicit cache_mode unless you have a specific reason — `REUSE` is right almost always. Bugs [#82830](https://github.com/godotengine/godot/issues/82830) (PackedScene cache inconsistency) and [#90344](https://github.com/godotengine/godot/issues/90344) hit some 4.x versions when explicit modes are passed; re-test if you tweak.

## Don't roll your own cache

ResourceLoader already deduplicates by path. A `static var SCENES: Dictionary[int, PackedScene]` populated at boot from `load(path)` is **redundant** — every entry is also in the ResourceLoader cache, and `load()` with `CACHE_MODE_REUSE` is the cheapest path back to that cache. The dedicated Dict adds bookkeeping with zero behavior delta.

Symptom: a registry autoload with both an `ALL: Array[ItemDef]` (the data table) and a `SCENES: Dictionary[int, PackedScene]` (the parallel "cache"). Fold or delete the second one.

## Don't `ResourceLoader.exists()` after boot validate

Boot validate already errors on missing paths. After boot, the only way `load()` can return null is asset deletion mid-runtime — at which point a redundant `exists()` guard gives the caller the same null they'd get from `load()` directly, just one hash lookup cheaper. Trust the boot pass:

```gdscript
# Bad — exists() is dead weight after _validate ran at autoload boot.
func get_pickup_scene(id: Id) -> PackedScene:
    if not ResourceLoader.exists(path): return null
    return load(path) as PackedScene

# Good — caller handles null from load() the same way.
func get_pickup_scene(id: Id) -> PackedScene:
    return load(path) as PackedScene
```

`exists()` still earns its keep **inside** boot validate (catches missing files at boot rather than first use) — drop it only on the runtime-lookup hot path.

## Editor-gate expensive validators

When boot validate instantiates scenes / walks resources (mesh decode, texture upload, sub-scene chains), wrap the expensive layer in `if OS.has_feature("editor"):`. Release trusts what the editor signed off. Full pattern + example: [`style.md`](style.md) M10a.

## No bidirectional `.tres ↔ .tscn` ext_resource

Engine bug C17 ([#98551](https://github.com/godotengine/godot/issues/98551)) — preload cycles can hang or load partial Resources. Cycles most often form as `.tres → .tscn → .tres`:

- `.tscn` ext_resources its data `.tres` (normal — pickup scene references the ItemDef).
- `.tres` adds an `@export var pickup_scene: PackedScene` pointing back at the `.tscn`.
- Engine resolves `.tres → .tscn → .tres → ...`.

Fix: carry the inverse direction as a **String path** (or, better, derive it by **convention** from a stable key — see [`dod.md`](dod.md) D7a convention-derived dispatch). `.tres` stays a leaf in the dependency graph; `.tscn` keeps its forward ref. See [`engine-bugs.md`](engine-bugs.md) C17 for the bug itself.

## UID files (`.uid` sidecars)

- Every imported resource has a UID; `.tscn` / `.tres` store it in the header. Godot 4.4+ adds `.uid` sidecar files so scripts and shaders participate too.
- `[ext_resource type="..." uid="uid://..." path="res://..." id="..."]` — UID is the resolution key, path is the editor-display fallback.
- **Commit `.uid` files to git**. Without them, cloning the project breaks every ext_resource reference on the new host.
- Renaming/moving a file with its `.uid` keeps references valid. Renaming without `.uid` silently breaks them.

## Misc

- `Resource.duplicate()` makes a shallow copy. Use when you need a per-instance mutable variant of a shared design-time Resource (e.g. per-door reinforcement HP state).
- `make_read_only()` on `Array` / `Dictionary` after boot validate locks the structure against accidental mutation. Pairs with `static var` — see [`engine-bugs.md`](engine-bugs.md) C2a.
- `ResourceLoader.has_cached(path)` is a free check — use it when you want to *decide* between sync `load()` and threaded prewarm, not when you already know you'll call `load()` regardless.
- Don't `await ResourceLoader.load_threaded_request(...)` — it's not a coroutine. Poll status instead. [`type-async.md`](type-async.md) covers signal/await traps.

## Sources

- [Godot 4 — Resources (tutorial)](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Logic preferences (best practices)](https://docs.godotengine.org/en/stable/tutorials/best_practices/logic_preferences.html)
- [Do Not Use Preload — theduriel](https://theduriel.github.io/Godot/Do-not-use---Preload)
- [UID changes coming to Godot 4.4 — official blog](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)
