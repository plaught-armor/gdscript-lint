# DOD by example: save/load (relational POD, ids not objects)

Worked example #6. Persistence is DOD's headline correctness win: **POD
serializes trivially; object graphs don't.** A save is a flat relational record of
ids and mutable deltas — not a blob of live references. Runnable:
[`tests/example_dod_save_proj/`](../../tests/example_dod_save_proj/), verified on
4.8.dev.

**In plain terms:** to save the game you write down *what changed* as plain
numbers and ids — the player's position, which items (by id) and how many, which
doors are open — never the live objects themselves. Loading rebuilds from that.

---

## The naive shape (and why it rots)

```gdscript
# Naive — save the live objects (tempting, but they don't serialize):
save.player = player_node              # a Node ref: doesn't serialize
save.held_item = current_weapon        # an ItemDef object: dangles / bloats
ResourceSaver.save(save, "user://s.tres")
```

Two failures: a `Node`/object ref can't round-trip (instance ids are
session-only — [Object docs](https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-get-instance-id)),
and a whole-Resource-graph save **breaks on a field rename** — "if you rename
things, you've lost all the data"
([godot-proposals #7567](https://github.com/godotengine/godot-proposals/discussions/7567)).

## The data-oriented shape

State is POD (D1); serialization is a pure transform (D6); the record is a flat
dict split **per concern** (D4), holding **ids not objects** (D3) and a **sparse
existence delta** for the world (D2):

```gdscript
static func to_record(s: GameState) -> Dictionary:
	return {
		"version": VERSION,
		"player_pos": s.player_pos,            # Vector2 — store_var keeps the type
		"inventory": s.inventory,              # Array[Vector2i] of (item_id, count) — ids (D3)
		"doors_opened": s.doors_opened,        # PackedStringArray — only OPENED doors (D2)
		"play_seconds": s.play_seconds,
	}
```

- **Ids, not objects.** `inventory` is `(item_id, count)` pairs; a registry
  resolves ids → `ItemDef` on use. A saved `ItemDef` object would dangle and
  bloat.
- **Sparse delta.** `doors_opened` lists only the doors that changed from default
  — 10k untouched doors cost zero bytes (existence-based, D2).
- **Binary `store_var` keeps types.** `Vector2i` and `PackedStringArray` survive
  exactly; JSON would collapse ints to floats and drop the Godot types.

**Atomic write** — `.tmp` then rename, so a crash mid-write leaves the prior save
intact:

```gdscript
static func write(path: String, rec: Dictionary) -> Error:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	f.store_var(rec)                           # no allow_objects = true
	f.close()                                  # close BEFORE rename
	return DirAccess.rename_absolute(tmp, path)
```

**Migration** — every field via `.get(key, default)`, so a v1 save missing
`play_seconds` loads clean:

```gdscript
s.inventory.assign(rec.get("inventory", []))   # untyped wire form → typed (C3)
s.play_seconds = rec.get("play_seconds", 0)    # v2 field; absent in v1 → 0
```

## Verified output

```
[demo] wrote save, Error=0 (0 = OK)
[demo] loaded: pos=(128,64) inv=[(1, 5), (3, 1)] doors=["room_42/north", "vault/main"] play=3725s
[demo] round-trip identical? true (binary store_var kept Vector2i + types)
[demo] loaded v1 save → play_seconds defaulted to 0 (no crash)
```

## What each rule bought

| Rule | Naive | Here | Win |
|---|---|---|---|
| D1 | data+behavior on a Node | POD `GameState` | serializes with no SceneTree |
| D3 | `ItemDef` object refs | `(item_id, count)` ids | round-trips; resolves via registry |
| D4 | one Resource blob | per-concern dict fields | a rename degrades, doesn't nuke |
| D2 | every door's state | `doors_opened` delta | only changes are stored |
| D6 | `save()` on the data | `SaveSystem.to_record()` | testable, no tree |

---

## Variants & use-cases

### Pick the serializer by trust + fidelity

| Mechanism | When | Security | Note |
|---|---|---|---|
| `FileAccess.store_var`/`get_var` (binary) | **trusted-local save files** (this example) | **safe** with `allow_objects = false` (default) | full Variant fidelity; compact |
| `JSON.stringify`/`parse_string` | **untrusted / cross-platform / web / mods** | **safe** (no Object path) | lossy: int↔float, no Vector*/enum/StringName; `JSON.from_native` (4.3+) tags Godot types |
| `ConfigFile` | settings / keybinds | ⚠️ **no safe gate** — RCE on edited file ([#80562](https://github.com/godotengine/godot/issues/80562)) | INI sections; keeps types; AES option |
| `ResourceSaver`/`.tres` | dev-time structured saves | ⚠️ `.tres` can embed a `Script` that runs on `load()` | typed `@export`; **breaks on field rename** |
| `var_to_str`/`str_to_var` | debug dumps only | ⚠️ **no safe gate at all** ([#80562](https://github.com/godotengine/godot/issues/80562)) | never on untrusted text |

**The security line that matters:** `allow_objects = true` (and `str_to_var` /
`ConfigFile` / `.tres` from an attacker-controlled file) construct Objects and run
their scripts on load — remote code execution (CVE-2019-10069). **Trusted-local**
(the player's own `user://`) tolerates binary `_with_objects = false`;
**untrusted** (shared saves, cloud sync, downloaded mods, multiplayer) → JSON, and
never `str_to_var`/`ConfigFile`/`ResourceLoader` on attacker text.

### Atomic & durable

- **`.tmp` + rename** (this example) survives an *app* crash mid-write. **OS crash
  / power loss** needs `fsync`, which isn't portable before Godot
  [PR #98361](https://github.com/godotengine/godot/pull/98361) — until merged,
  **double-buffer** (alternate `slot_a` / `slot_b`) for full durability.
- `OS.set_use_file_access_save_and_swap(true)` gives the engine's save-and-swap,
  but the same `fflush ≠ fsync` caveat applies.
- Write to **`user://`**, never `res://` (read-only in an exported build).

### Versioning & migration

- Embed `version`; read every field with `.get(key, default)` (additive-with-
  defaults) so old saves load. This is the prevailing community pattern
  ([Coding Quests](https://codingquests.io/blog/how-to-build-a-save-system-in-godot-4)).
- For structural changes, keep the **old class as a schema**, load via it, transform
  forward, resave (GDQuest's "mirror a DB migration"
  [recipe](https://www.gdquest.com/library/save_game_godot4/)).
- Resource-graph saves *can't* migrate a field rename — another reason the dict
  record wins.

### Web / export quirks

- HTML5 persists `user://` in **IndexedDB** — needs cookies enabled, breaks in
  private browsing; the engine auto-syncs async/best-effort. For a critical save,
  `JavaScriptBridge.force_fs_sync()` then `await get_tree().process_frame` before
  navigation. iOS Safari still refuses IndexedDB in iframes
  ([#38498](https://github.com/godotengine/godot/issues/38498)).

### Use-case sheet

| Use-case | Mechanism | Why / gotcha |
|---|---|---|
| settings / keybinds | `ConfigFile` | sections + types; trusted-source only (RCE on edit) |
| save slots (full state) | dict record via `store_var`, or typed `Resource` | split a `slot.meta` (timestamp/thumbnail) from the blob so the slot UI doesn't deserialize everything |
| inventory | `[(item_id, count)]` + registry | D3; `duplicate()` per-instance state (durability), pair `make_read_only()` on the registry |
| large world state | sparse delta dict keyed by stable id | D2 — only changes stored; stable ids not NodePaths |
| autosave | snapshot to POD on main thread → `WorkerThreadPool` writes | never touch SceneTree from the worker; atomic write |
| quest flags | `Dictionary[StringName, bool]` | append-only = new key, no migration; centralize the flag names |
| thumbnails | `await RenderingServer.frame_post_draw` → `save_jpg` sidecar | without `await` you capture a blank pre-draw frame |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_save_proj --import   # once
"$GODOT" --headless --path tests/example_dod_save_proj
```
