# Part VIII — Persistence (save & load)

How to write runtime state to disk and read it back — safely, compactly, and
without losing old saves. Distinct from [Part VI](06-resource-loading.md), which
loads designer-*authored* assets; this is the *save game* path.

The record's **shape** — POD, ids-not-objects, relational, sparse delta — is a
data-oriented question, worked end to end in the [save/load example](ex-save.md)
(D1/D3/D4/D6). This part is the machinery *around* that shape, and it has one
genuinely dangerous corner and one place the common wisdom is simply wrong:

- **The dangerous corner:** deserializing an Object from a save is remote code
  execution. Most "load my save" tutorials reach for the unsafe call without
  saying so.
- **The wrong wisdom:** "a more compact wire format makes the smallest save."
  Measured, it doesn't — Godot's binary blob is the *largest raw* form and the
  *smallest on disk* once you add the compression layer, which costs almost
  nothing.

Draws from [`../rules/persistence.md`](../rules/persistence.md).

---

## 8a. Rule of thumb

**In plain terms:** turn the game state into plain bytes with the engine's binary
serializer (it keeps every Godot type and is the fastest), squeeze those bytes
with zstd (tiny, fast), and write to a temp file then rename over the real one so
a crash can't shred your save. On load, do it in reverse — and never let the
loader build an Object out of bytes a player could have edited.

> **Binary `var_to_bytes` for bytes. Relational dict for the record. zstd for
> size. tmp+rename for the write. `.get(k, default)` for migration. NEVER
> deserialize an Object from a save a player can touch.**

Five independent decisions, one per stage. They compose; this part takes them in
the order the bytes flow.

## 8b. Serialization — what encodes the bytes

| Option | Type fidelity | Safe by default | Cross-lang | Speed | Verdict |
|---|---|---|---|---|---|
| `var_to_bytes` / `bytes_to_var` (binary Variant) | full (`Vector2i`, `Packed*`, typed) | **yes** — rejects Objects | Godot-only | native C++, fastest | **default for a Godot-only save** |
| JSON | lossy — all numbers → `float64`, loses Godot types | yes | yes | med | settings / interop only |
| `ConfigFile` | via `var_to_str` | **no — RCE** (#80562) | no | slow | trusted input only |
| `ResourceSaver` `.res`/`.tres` | full | **no — RCE on load** + rename data-loss | no | med | designer data, not saves |
| custom binary (`StreamPeerBuffer`) | manual | yes | manual | fastest+smallest | profiler-pointed only |

The default is binary `store_var`/`var_to_bytes`. It keeps full type fidelity
(`Vector2i` stays `Vector2i`, a `PackedStringArray` stays packed — JSON would
collapse every int to a float and drop the typed containers), it's native C++ so
it's the fastest option by a wide margin (§8d numbers), and its safe form is the
*default* form. `store_var(rec)` writes straight to a file; `var_to_bytes(rec)`
returns a `PackedByteArray` for when a compression layer sits between serialize
and disk — same encoding, pick by whether you need the bytes in hand.

One deliberate style inversion: the record is read back with `rec.get(key,
default)`, not `rec["key"]`. A save file is exactly the *external / optional*
boundary where `.get`-with-default is correct ([Part III / rules S7](../rules/style.md)
otherwise mandate bracket access on known schemas) — a v1 file legitimately
lacks a v2 key, and the default is the migration (§8f).

## 8c. Security — never deserialize an Object from a save

This is the one corner of persistence that is *dangerous*, not just untidy. A
save file is attacker-controlled the moment it sits on a disk the player can
reach — local tamper, a cloud-sync swap, a "save editor" off a forum. If your
load path can construct an **Object** from those bytes, it constructs a *forged*
object and **runs its embedded script** — full remote code execution
([CVE-2019-10069](https://nvd.nist.gov/vuln/detail/CVE-2019-10069), CVSS 9.8).
That CVE number indexes a narrower bug than it sounds — the engine's *own*
object-decode gate failing on the multiplayer path (Godot ≤3.1, fixed in 3.2 by
[#27398](https://github.com/godotengine/godot/pull/27398)) — but it is the
clearest proof the danger is real: the same hole bit the engine itself. The fix
that protects *saves* is a different PR. [#27485](https://github.com/godotengine/godot/pull/27485)
added the `allow_objects` gate to the serializer calls you make here —
`bytes_to_var`, `get_var`, `store_var` — and flipped them to **reject Objects by
default** ("object variant... should never be the default"). That landed in Godot
3.2, was cherry-picked to 3.1.1, and is carried into every 4.x. So on 4.x the gate
is correct out of the box; the only road back to RCE is to *opt in* on untrusted
bytes — the RCE column below — a choice you make, never a default you inherit.

| API | Safe form | RCE form |
|---|---|---|
| bytes | `bytes_to_var(b)` (`allow_objects = false`) | `bytes_to_var_with_objects(b)` |
| file | `f.get_var(false)` | `f.get_var(true)` |
| string | — (no safe gate) | `str_to_var(s)` |
| config | — (no safe gate) | `ConfigFile` value decode |
| resource | — | `ResourceLoader.load("user://save.tres")` |

Three things to internalize:

1. **The safe path is the default path.** `bytes_to_var(b)` and `f.get_var()`
   reject Objects unless you go out of your way — the unsafe path is a *different
   function name* (`bytes_to_var_with_objects`) or an explicit `true`. Write the
   obvious call and you're safe; you have to *try* to be vulnerable. So never
   "just add `true` to make it work" — if decoding fails without it, your save is
   carrying an Object it shouldn't (see 4).
2. **`str_to_var` and `ConfigFile` have no safe gate at all** ([#80562](https://github.com/godotengine/godot/issues/80562)).
   There is no `allow_objects = false` to pass. So they are fine for a settings
   file the game itself writes and the player is *expected* to edit, and unfit
   for anything a save's integrity depends on. Want a config-shaped save? Encode
   it with gated binary `bytes_to_var`, not `ConfigFile`.
3. **`ResourceSaver`/`.tres` saves are RCE on *load*.** Loading a resource
   instantiates it and runs any embedded/attached script. A `.tres` save you let
   the player keep is the same hole wearing a different hat — another reason saves
   are dict records, not serialized Resources.

And the structural point (4): **a save never needs an Object in the first
place.** Store ids and POD (D3); resolve ids → live `Def` through a registry on
load. If you find yourself wanting `allow_objects = true`, you skipped the
record-shape step in [ex-save](ex-save.md), and the fix is upstream — flatten to
ids — not a dangerous flag downstream.

## 8d. Compression — measured, and the wisdom it overturns

Compression is a layer *over* serialization, independent of the encoder: bytes
in, smaller bytes out. The interesting result is what it does to the
"which format is smallest" question.

**The common wisdom** is that a more compact wire format — JSON, or a
purpose-built binary one — yields the smallest save, and the engine's
`store_var` is the fat, lazy option. The first half is half-true and the
conclusion is wrong.

**Measured** ([`tests/bench_save_proj/bench_save.gd`](../tests/bench_save_proj/bench_save.gd),
4.8.dev, a `GameState` of scalar header + an inventory of N `{name, count}` rows,
best-of-7):

Encoders, N = 1000 items:

| encoder | encode ms | decode ms | bytes | vs store_var |
|---|---|---|---|---|
| **store_var** (binary) | **0.230** | **0.299** | 60160 | 1.00× |
| json (lossy) | 0.653 | 0.500 | 30876 | 0.51× |

So yes — raw, the binary blob is the *biggest* (60 KB vs JSON's 31 KB): Variant
encoding tags every value with its type and repeats dict keys. Now add the
compression layer to that same 60 KB blob:

| mode (`FileAccess.COMPRESSION_*`) | ratio | out bytes | compress ms | decompress ms |
|---|---|---|---|---|
| `FASTLZ` (0) | 14.4% | 8647 | 0.028 | 0.008 |
| `DEFLATE` (1) | 8.3% | 4999 | 0.246 | 0.035 |
| **`ZSTD` (2)** | **3.9%** | **2375** | 0.034 | 0.013 |
| `GZIP` (3) | 8.3% | 5011 | 0.245 | 0.038 |

**The 60 KB binary blob becomes 2.4 KB — smaller than raw JSON, and smaller than
a hand-packed wire format would be — for ~0.03 ms of compression on top of the
fastest encode.** The Variant tagging that bloats the raw blob is exactly what
zstd eats for breakfast: repeated keys and type tags are maximally compressible.
The ordering holds at small saves too (N = 50: store_var+zstd 328 B still beats
the next-smallest candidate at 704 B) — the gap narrows with less redundancy but
doesn't invert. **A compact encoder buys you a smaller *raw* file and a slower
encode; binary + zstd wins the only number that reaches disk.**

Within the compression layer, **zstd dominates on both axes** here — 3.9% vs
deflate/gzip's 8.3% ratio, *and* ~7× faster to compress (Godot's deflate is
slow). gzip is deflate with a wrapper — no reason to pick it. fastlz is the
fastest but ~4× worse ratio: reach for it only if you're writing *per frame*
(streaming autosave), never for a save the player triggers.

Two gotchas the write path must handle:

1. **`PackedByteArray.decompress(size, mode)` needs the original uncompressed
   size** — the zstd/fastlz frame Godot writes doesn't store it. Put the length
   in an 8-byte `store_64` header before the compressed bytes and read it back
   first. `decompress_dynamic()` avoids the header **but rejects zstd and
   fastlz** (deflate/gzip/brotli only), so it's not an option for the recommended
   mode. (`FileAccess.open_compressed` *does* write its own header, but it only
   reads files Godot itself wrote and is block-based — the explicit `compress()`
   + manual header keeps the format yours and composes with the atomic write.)
2. **Godot hardcodes zstd level 3** ([#77820](https://github.com/godotengine/godot/issues/77820)),
   so its ratios trail the command-line tool. For a fat save, raise
   `ProjectSettings → compression/formats/zstd/{compression_level,
   long_distance_matching}` — at save-file sizes the extra compression time is
   noise, so a higher level is nearly free.

## 8e. Durability — atomic write

Write to `path + ".tmp"`, then `DirAccess.rename_absolute(tmp, path)`. Rename is
atomic on every OS, so a crash mid-write leaves the *previous* save intact rather
than a half-written corrupt one. Close the file *before* the rename.

```gdscript
static func write(path: String, rec: Dictionary) -> Error:
	var blob: PackedByteArray = var_to_bytes(rec)            # binary, full fidelity
	var f: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_64(blob.size())                                  # decompress() needs the size
	f.store_buffer(blob.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()                                                # close BEFORE rename
	return DirAccess.rename_absolute(path + ".tmp", path)
```

Limit: rename survives a *process* crash, not power loss / OS crash mid-flush —
that needs `fsync`, not portable before [#98361](https://github.com/godotengine/godot/pull/98361).
For power-loss safety, **double-buffer** two slots (`slot_a` / `slot_b`) plus a
tiny "newest-and-valid" pointer, and never overwrite the slot you'd fall back to.
Always write to **`user://`**, never `res://` (read-only in an exported build).
Web/export quirks (HTML5 IndexedDB, `JavaScriptBridge.force_fs_sync()`) are in
[ex-save](ex-save.md#web--export-quirks).

## 8f. Migration — additive record, version byte for format breaks

Two different changes, two different mechanisms:

- **Adding a field** is additive-with-defaults. Embed a `"version": int`, read
  every field via `rec.get(key, default)`, and a v1 save that predates a v2 field
  loads clean (defaulted), no crash. This is the prevailing community pattern and
  it covers the common case.
- **Changing the byte framing** is *not* the same problem, and `.get` can't save
  you. The day you add compression, switch encoders, or change the header, old
  files no longer *decode at all* — there's no dict to pull defaults from. Guard
  against it before you ship v1: write a **magic + format-version byte first**,
  before the payload, and branch the read path on it (raw `store_var` vs
  zstd-framed). Adding the compression layer in §8d/§8e is exactly such a break;
  in a shipped game it needs that leading byte or every existing save bricks.
- **Rename ≠ migrate.** Renaming a field in a `ResourceSaver` graph save silently
  drops the value ([godot-proposals #7567](https://github.com/godotengine/godot-proposals/discussions/7567));
  a dict record just leaves the old key unread. The third reason saves are dict
  records (D4), not serialized Resources.

---

## Where the pieces live

- **Record shape, runnable** — [ex-save](ex-save.md): POD, ids-not-objects,
  relational split, sparse delta, the full naive→DOD walkthrough, a use-case
  sheet (settings / slots / inventory / autosave / quest flags / thumbnails), and
  web-export quirks.
- **Compression numbers, reproducible** — [`tests/bench_save_proj/bench_save.gd`](../tests/bench_save_proj/bench_save.gd),
  logged in [BENCH.md](../tests/BENCH.md).
- **Terse flag conditions** — [`../rules/persistence.md`](../rules/persistence.md).

## Sources

- [Godot — `FileAccess`](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) · [`PackedByteArray`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html)
- [CVE-2019-10069](https://nvd.nist.gov/vuln/detail/CVE-2019-10069) deserialization RCE · [#80562](https://github.com/godotengine/godot/issues/80562) `str_to_var`/`ConfigFile` ungated
- [#77820](https://github.com/godotengine/godot/issues/77820) zstd level-3 ratio · [#98361](https://github.com/godotengine/godot/pull/98361) `fsync`
