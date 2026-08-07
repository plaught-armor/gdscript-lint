# GDScript — Persistence (Save / Load)

Persist runtime user state to disk + read it back. Distinct from
[`resource-loading.md`](resource-loading.md) — that loads designer-*authored*
assets; this is the *save game* write/read path. The record's **shape** is a
data-oriented-design question and lives in [`dod.md`](dod.md): D1 (POD record,
no behavior), D3 (store ids, not object pointers), D4 (relational `SaveSlot` —
per-concern containers, not one blob), D6 (serialize via a pure transform, not a
method on the data). This doc covers the four things *around* that shape:
**serialization choice, security, compression, durability + migration.**

Worked example: [`tests/example_dod_save_proj/`](../tests/example_dod_save_proj).
Measured numbers: [`tests/bench_save_proj/bench_save.gd`](../tests/bench_save_proj).

## 0. Ownership — three layers, who touches what

Recurring confusion: "where does the logic that turns saved IDs back into
objects live, and does it run *after* load finishes?" Answer: it **is** the load
— its second half — and it belongs to the object *owner*, never the save class.

| Layer | Owns | Touches |
|---|---|---|
| Save/load class | bytes ↔ plain dict of POD (ints, `Vector2`, `String`) | `get_var(false)`, `var_to_bytes` — **never an Object ref** |
| Owning system (Manager / spawner / registry) | dict ↔ live objects | reads ids, `get_def(id)` / `instantiate`, pours remaining POD fields onto the fresh instance, rebuilds graph |
| The objects | their own fields | nothing about disk |

- **Load = two halves, not "load then a separate assign step":** (1) bytes → plain
  dict; (2) dict → live objects. Half 2 is the reconstruction — spawn from id,
  then assign the *rest* of the POD (position `Vector2`, name `String`, …) onto
  the new instance. Same pass, all fields, not just the id.
- **Why the owner, not the save class:** the save class holding object refs to
  rebuild is exactly the scope leak that forces `get_var(true)`. Keep it a dumb
  data pump — POD in, POD out, no Object it could be tricked into constructing
  (§2). The Manager already owns object lifecycle (dod.md D4/D8) → natural home
  for the rebuild loop. Not overengineering; the correct seam.

## Rule of thumb

> **Binary `var_to_bytes` for bytes. Relational dict for the record. zstd for
> size. tmp+rename for the write. `.get(k, default)` for migration. NEVER
> deserialize an Object from a save a player can touch.**

## 1. Serialization — what encodes the bytes

| Option | Type fidelity | Safe by default | Cross-lang | Speed | Verdict |
|---|---|---|---|---|---|
| `var_to_bytes` / `bytes_to_var` (binary Variant) | full (`Vector2i`, `Packed*`, typed) | **yes** — rejects Objects | ⊥ Godot-only | native C++, fastest | **default for a Godot-only save** |
| JSON | lossy — all numbers → `float64`, loses Godot types | yes | yes | med | settings / interop only, ⊥ typed game state |
| `ConfigFile` | via `var_to_str` | **⊥ RCE** (no `allow_objects` gate, #80562) | no | slow | ⊥ untrusted input |
| `ResourceSaver` `.res`/`.tres` | full | **⊥ RCE on load** (embedded script runs) + field-rename data loss | no | med | designer data, ⊥ save games |
| custom binary (`StreamPeerBuffer`) | manual | yes | manual | fastest + smallest | only profiler-pointed |

`store_var(rec)` (file-level) and `var_to_bytes(rec)` (in-memory `PackedByteArray`)
use the same encoding — reach for the bytes form when a compression layer sits
between serialize and disk (§3).

Dict-access on the record uses `rec.get(key, default)` here **on purpose** — the
save file is an *external/optional* boundary (a v1 file legitimately lacks a v2
key), the one case where `.get` with a default beats bracket access (cf.
[`style.md`](style.md) S7/P9: known schemas use `rec["key"]`).

## 2. SECURITY — never deserialize an Object from a save (headline)

A save file is attacker-controlled the moment it lives on a disk the player can
reach (local tamper, cloud-sync swap, a downloaded "save editor"). Deserializing
an **Object** from those bytes constructs a forged object **and runs its embedded
script** — remote code execution (CVE-2019-10069).

| API | Safe form | RCE form |
|---|---|---|
| bytes | `bytes_to_var(b)` — `allow_objects = false` | `bytes_to_var_with_objects(b)` |
| file | `f.get_var(false)` | `f.get_var(true)` |
| string | — (no safe gate) | `str_to_var(s)` (#80562) |
| config | — (no safe gate) | `ConfigFile` value decode (#80562) |
| resource | — | `ResourceLoader.load(save.tres)` runs embedded scripts |

- The unsafe byte/file path is a **separate function / a `true` arg** — so the
  safe default is what you get by writing the obvious call. Keep it that way.
- `str_to_var` and `ConfigFile` have **no safe gate at all** → never feed them a
  player-reachable file. Use binary `bytes_to_var` (gated) instead.
- A save **never needs Objects** anyway — store ids + POD (D3). If you think you
  need to serialize an Object, you've skipped the D1/D3 record-shape step.

## 3. Compression — orthogonal layer over any byte output

Serialize → compress → write. Decompress → deserialize. Independent of §1.

**Measured** (`tests/bench_save_proj/bench_save.gd`, 4.8.dev, GameState + 1000
inventory items, best-of-7). The binary blob is the *largest raw* form but
compresses smallest — **PERF**:

| mode (`FileAccess.COMPRESSION_*`) | ratio | compress | decompress | note |
|---|---|---|---|---|
| `FASTLZ` (0) | 14.4% | fastest | fastest | weak ratio; only if writing per-frame |
| `DEFLATE` (1) | 8.3% | ~7× slower than zstd | slow | — |
| **`ZSTD` (2)** | **3.9%** | fast | fast | **default — best ratio AND speed** |
| `GZIP` (3) | 8.3% | slow | slow | deflate + a header; no reason over zstd |
| `BROTLI` (4) | — | decompress-only | — | can't compress from GDScript |

Two gotchas the write path must handle:

1. **`PackedByteArray.decompress(size, mode)` needs the ORIGINAL size** — the
   zstd/fastlz frame Godot writes carries none. Store the uncompressed length
   yourself (an 8-byte `store_64` header before the compressed bytes).
   `decompress_dynamic()` avoids the header **but rejects zstd/fastlz** (deflate/
   gzip/brotli only) → not an option for the recommended mode.
2. **Godot hardcodes zstd level 3** ([#77820](https://github.com/godotengine/godot/issues/77820))
   — ratios trail the command-line tool. Crank
   `ProjectSettings → compression/formats/zstd/{compression_level,
   long_distance_matching}` for fat saves; compression time is negligible at
   save-file sizes (KB–MB), so a higher level is nearly free.

`FileAccess.open_compressed(path, mode, comp)` writes its own size header and is
the terser path, but it **only reads files Godot itself wrote** and is
block-based; the explicit `compress()` + manual header keeps the format under
your control and composes with the atomic write below.

## 4. Durability — atomic write

Write to `path + ".tmp"`, then `DirAccess.rename_absolute(tmp, path)`. Rename is
atomic on every OS → a crash mid-write leaves the **previous** save intact
instead of a half-written corrupt one.

```gdscript
var f: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
if f == null:
    return FileAccess.get_open_error()
f.store_64(blob.size())   # decompress() needs the original size
f.store_buffer(blob.compress(FileAccess.COMPRESSION_ZSTD))
f.close()
return DirAccess.rename_absolute(path + ".tmp", path)
```

Limit: rename survives a *process* crash, not power loss / OS crash mid-flush —
that needs `fsync`, which Godot still doesn't expose — [#98361](https://github.com/godotengine/godot/pull/98361)
is an **open, unmerged PR** (verified 2026-07), not a version boundary you can be past.
For power-loss safety, double-buffer two slots (`save_a` / `save_b`) + a small
"which is newest + valid" pointer file, and never overwrite the slot you'd fall
back to.

## 5. Migration — additive record + version byte

- **Version field** in the record (`"version": int`). Read every field via
  `rec.get(key, default)` → a v1 save that predates a v2 field loads clean
  (defaulted), not a crash. Additive-with-defaults covers field *additions*.
- **A format break is different from a field addition.** Changing the *byte
  framing* — adding compression, switching encoder, changing the header — means
  old files no longer parse, and `.get(k, default)` can't save you because you
  can't even decode the dict. Put a **magic + format-version byte FIRST**, before
  the payload, and branch read-path on it (old raw `store_var` vs new
  zstd-framed). Decide this before you ship v1, not after a player's save breaks.
- **Rename ≠ migrate.** Renaming a field in a `ResourceSaver` graph save silently
  drops the old value; a dict record degrades gracefully (old key just goes
  unread). One more reason saves are dict records (D4), not serialized Resources.

## Sources

- [Godot — `FileAccess`](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) (`store_var`/`get_var`, `open_compressed`, `CompressionMode`)
- [Godot — `PackedByteArray.compress` / `decompress` / `decompress_dynamic`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html)
- [CVE-2019-10069](https://nvd.nist.gov/vuln/detail/CVE-2019-10069) — Object-deserialize RCE; the CVE number indexes the multiplayer-path instance ([#27398](https://github.com/godotengine/godot/pull/27398)). The **save-path** serializer gate — `bytes_to_var`/`get_var`/`store_var` default-reject Objects — is [#27485](https://github.com/godotengine/godot/pull/27485), Godot 3.2 (cherry-picked 3.1.1), carried into 4.x. · [#80562](https://github.com/godotengine/godot/issues/80562) `str_to_var`/`ConfigFile` still ungated
- [#77820](https://github.com/godotengine/godot/issues/77820) zstd/gzip ratio vs cmd tools (level 3) · [#98361](https://github.com/godotengine/godot/pull/98361) `fsync` (open PR, unmerged 2026-07)
