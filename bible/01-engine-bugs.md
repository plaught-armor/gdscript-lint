# Part I — Engine bugs

Code that compiles fine and crashes, leaks, or silently corrupts at runtime.
Each entry: symptom → minimal repro → fix → Godot issue # → **version status**
(live, or fixed-in-X so you can drop the workaround).

Draws from [`../rules/engine-bugs.md`](../rules/engine-bugs.md).

> **Version status verified 2026-06, and several entries re-tested empirically on
> Godot 4.8.dev** (`custom_build.fd98f8452`) with the repro scripts in
> [`../tests/`](../tests/) (`repro_typed_collections.gd`, `repro_lifecycle.gd`).
> The engine moves: re-running the repros found that **C1, C2, and the `.filter()`
> half of C3 no longer reproduce on 4.8.dev**, while C3's `.map()` half, C7, C14,
> and C17 are still live (C17 now as a silent partial-load rather than a hang).
> The lifecycle entries C5, C8, C10, H8, and M9 were re-run and behave as their
> status claims on 4.8.dev; C6's crash is gone but the coroutine is now silently
> *dropped* rather than resumed (see its entry). Of the previously-unverified tail:
> C4 resolves to **invariant** typed arrays (covariant assignment is a compile
> error), C13 (unparented `Node.new()` leak) is **confirmed**, and H12 is
> **confirmed fixed**. Where a re-test changed or refined the verdict it's called
> out inline
> and in the summary table. The table is the fast-path: if your minimum Godot is
> past the fix-version, drop the workaround; otherwise keep it. **Re-test on your
> own target** — "fixed on 4.8.dev" is not a promise about 4.7 or 4.9.
>
> **Order:** the full sections below are the bugs **still live on current Godot**.
> Ones fixed in a known version are condensed under *"Fixed in a known version"*
> (keep their workaround only if your min Godot predates the fix); the
> version-status table at the end is the complete verdict.

---

## 1a. Typed `.filter()` / `.map()` return untyped `Array`

**In plain terms:** you'd expect filtering or transforming a typed list to give
you back a typed list of the same kind. It doesn't — the result is a generic
list, and trying to drop it straight into a typed slot blows up or silently
loses the type. Use the dedicated `.assign()` method to copy the result into
your typed list.

**Symptom.** Calling `.filter()` or `.map()` on an `Array[T]` returns a
*plain* `Array`, not an `Array[T]`. Assigning the result to a typed local with
`=` raises a type-mismatch error at runtime, or — worse — silently downgrades
the typing.

**Repro.**

```gdscript
# Repro — typed .filter()/.map() returns an untyped Array (#72566).
var queue: Array[BattlePawn] = [...]

# This errors at runtime: "Trying to assign array of type 'Array' to 'Array[BattlePawn]'"
var result: Array[BattlePawn] = queue.filter(func(p): return is_instance_valid(p))
```

**Fix.** Use `Array.assign()`, which performs the typed copy:

```gdscript
var result: Array[BattlePawn] = []
result.assign(queue.filter(func(p): return is_instance_valid(p)))
```

The matching DOD/style point: type the *destination* container (don't take
untyped `Array` "for flexibility" — see **H10b** in `style.md`), then `assign()`
at the boundary.

**Issue / status.** [#72566](https://github.com/godotengine/godot/issues/72566).
**Re-tested on Godot 4.8.dev — `.filter()` is fixed, `.map()` is NOT.** Measured
with `get_typed_builtin()` on the result
(`repro_typed_collections.gd` → C3, `repro_lifecycle.gd` → C3.map):

| Call on `Array[int]` | result element type on 4.8.dev |
|---|---|
| `.filter(...)` | `TYPE_INT` — **typed, fixed** |
| `.map(...)` | `0` (untyped) — **still live** |

So on 4.8.dev you can drop the `assign()` dance for `.filter()`, but `.map()`
still hands back a plain `Array` and needs `assign()` exactly as before. Until your
minimum Godot has both fixed, the safe habit is unchanged: `assign()` into a typed
destination. (The same untyped-result trap applies to `range()` — see C14.) Lint
flag: **C3**.

---

## 1b. `await` on a freed object leaks or crashes

**In plain terms:** `await` pauses your function until something happens. While
you're paused, the object you were waiting on can be deleted. When the code
resumes, touching that now-dead object crashes the game. Always re-check that
the object is still alive right after the `await`.

**Symptom.** Awaiting a signal on a Node that gets freed before the signal
fires either leaks the coroutine frame or crashes the resume site. After
*any* `await` involving a Node, the Node reference may point at a freed
object — or, worse, at a *different* object that reused the instance id
(see C8).

**Repro.**

```gdscript
# Repro — await on a freed object leaks or crashes.
func chase(target: Node) -> void:
    await get_tree().create_timer(2.0).timeout
    target.take_damage(10)   # target may be freed; crash or wrong-object hit
```

**Fix.** Always `is_instance_valid()` after the resume, before touching the
awaited target:

```gdscript
func chase(target: Node) -> void:
    await get_tree().create_timer(2.0).timeout
    if not is_instance_valid(target):
        return
    target.take_damage(10)
```

Belt-and-suspenders: check type too (`if target is Enemy`), because instance
id reuse may resolve to a live object of a different class (C8).

**Issue / status.** [#72629](https://github.com/godotengine/godot/issues/72629).
**By design** — the validity check is the prescribed pattern. **Confirmed on Godot
4.8.dev** (`tests/repro_async_proj/`): after an `await` that spans the target's
`free()`, `is_instance_valid(target)` returns `false`, so the guard correctly
blocks the use-after-free — touching `target.*` without it is the crash. Lint
flag: **C5**.

---

## 1c. Freed-object instance-id reuse

**In plain terms:** every object gets a numeric tag. When you delete an object
the engine can hand that same tag to a *different* new object. If you held the
old reference, you might end up calling methods on a stranger — and the usual
"is this null?" check tells you everything is fine. The fix is to store the
tag (the integer ID), then re-look-it-up at the moment you actually use it,
and check the type too.

**Symptom.** Storing a `Node` reference, freeing the Node, then later
resolving the reference yields a *different live object* that recycled the
same instance id. Truthiness and `== null` will tell you the ref is "alive";
a method call dispatches to the wrong object.

**Repro.**

```gdscript
# Repro — freed-object id reuse resolves a stale ref to the wrong object.
var _attacker: Node = null

func remember(src: Node) -> void:
    _attacker = src

func retaliate() -> void:
    # `_attacker` may now be a different Node entirely.
    if _attacker:
        _attacker.take_damage(5)   # wrong target
```

**Fix.** When a reference crosses systems, sits in a signal payload, gets
serialized, or outlives the holder's subtree, store the *integer id* and
re-resolve at use site with a type check:

```gdscript
var _attacker_id: int = 0

func remember(src: Node) -> void:
    _attacker_id = src.get_instance_id() if src != null else 0

func retaliate() -> void:
    var s: Object = instance_from_id(_attacker_id)
    if s is Enemy and s.is_alive():
        s.take_damage(5)
```

This is the same shape as DOD rule **D3** — reference by ID, resolve at use
site. Sibling refs inside one scene tree can still be direct typed refs;
this rule is about refs that *escape* a subtree's lifecycle.

**Issue / status.** [#32383](https://github.com/godotengine/godot/issues/32383).
**By design** — id reuse is part of the object lifecycle. Lint flag: **C8**.

---

## 1d. RefCounted circular references leak silently

**In plain terms:** these objects clean themselves up when nothing points at
them anymore. If two of them point at each other, each one is keeping the
other alive — so neither ever gets cleaned up. There's no warning; memory just
slowly fills. Break the loop by having one side hold a "weak" reference or an
ID instead.

**Symptom.** Two `RefCounted` instances each holding a typed ref to the other
never reach refcount zero. Both objects, plus everything they own, leak for
the program's lifetime. No error, no warning — only `Performance.OBJECT_COUNT`
climbing.

**Repro.**

```gdscript
# Repro — two RefCounteds referencing each other leak silently (no cycle GC).
class_name Node_ extends RefCounted
var neighbour: Node_

func link(a: Node_, b: Node_) -> void:
    a.neighbour = b
    b.neighbour = a   # cycle; both leak when locals go out of scope
```

**Fix.** Break the cycle in one of two ways:

1. **`weakref()` one direction.** The weak side returns `null` if its target
   is gone:

   ```gdscript
   class_name Node_ extends RefCounted
   var neighbour_ref: WeakRef

   func neighbour() -> Node_:
       return neighbour_ref.get_ref() if neighbour_ref else null
   ```

2. **Entity IDs** — store `get_instance_id()` on one side, resolve at use
   site. Same shape as C8. See [`../rules/dod.md`](../rules/dod.md) D3.

**Issue / status.** [#7038](https://github.com/godotengine/godot/issues/7038).
**Live — confirmed on Godot 4.8.dev.** Creating 2000 mutually-referencing
`RefCounted` pairs and dropping every reference leaked exactly ~4000 objects
(`OBJECT_COUNT` delta, `repro_lifecycle.gd` → C7): GDScript reference-counts but
does **not** collect cycles, so a mutual reference keeps both alive forever. Break
one direction with `weakref()` or an integer id. Lint flag: **C7**.

---

## 1e. `sort_custom` must be strict `<`

**In plain terms:** when you write a custom sort, your comparison function must
say "strictly less than" — never "less than or equal." Otherwise the sort can
spin forever or read past the end of the array. And don't assume equal items
keep their original order; if order matters between ties, add a tiebreaker.

**Symptom.** A comparator that returns `<=` (or `>=`) instead of `<` (or `>`)
produces non-deterministic ordering, infinite loops, or out-of-bounds reads on
some inputs. `Array.sort()` is also **not stable** — equal elements may shuffle.

**Repro.**

```gdscript
# Bad — non-strict comparator.
arr.sort_custom(func(a, b): return a.priority <= b.priority)

# Bad — relies on stability that doesn't exist.
arr.sort_custom(func(a, b): return a.priority < b.priority)   # ties shuffle
```

**Fix.** Strict `<` plus an explicit tiebreaker that preserves the order you
expect:

```gdscript
arr.sort_custom(_by_priority)

# Named comparator with an explicit tiebreaker.
func _by_priority(a: Pawn, b: Pawn) -> bool:
    if a.priority != b.priority:
        return a.priority < b.priority
    return a.id < b.id   # tiebreaker — strict, deterministic on ties
```

**Issue / status.** [#58878](https://github.com/godotengine/godot/issues/58878).
**Live** (the underlying sort algorithm choice and the non-strict comparator
behaviour are unchanged). Lint flag: **C11**.

---

## 1f. `assert()` is stripped in release

**In plain terms:** `assert()` is a developer-only check — when you build the
final shipped game, the whole line is *deleted*. If you tucked any real work
inside it ("check this AND do this"), that work simply doesn't happen for
players. Reserve `assert` for sanity checks; use a regular `if` for anything
the game actually needs.

**Symptom.** Code inside `assert()` doesn't run in release builds. Anything
the assert was load-bearing for — a side effect, a runtime invariant check —
silently no-ops on the shipped binary.

**Repro.**

```gdscript
# Bad — assert is stripped; debug-only behaviour.
assert(_validate_state(),  "state corrupted")
```

**Fix.** `assert()` belongs only on developer-time invariants you genuinely
want stripped. For real runtime validation, use an `if` + `push_error` +
optionally `OS.crash()` for fail-loud at boundaries:

```gdscript
if not _validate_state():
    push_error("[%s] state corrupted" % name)
    OS.crash("state corrupted")
```

**Issue / status.** **By design** — `assert()` is a debug aid. No issue number.
**Confirmed empirically** (`tests/repro_assert_proj/`): the same scene, where
`assert()` calls a function that flips a flag, was run under both a debug build
(4.8.dev editor) and a release build (the `linux_release.x86_64` export template,
4.5.beta5 — the only release binary on hand; assert-stripping is a version-stable
compile-time behavior). Debug: the flag was set (`assert-body-ran=true`,
`is_debug=true`). Release: the flag was **not** set (`assert-body-ran=false`,
`is_debug=false`) — so the entire `assert()`, *including its argument expression*,
is compiled out. Never put a load-bearing side effect inside `assert()`. Lint
flag: **C12**.

---

## 1g. `.tres ↔ .tscn` preload cycles

**In plain terms:** if a data file points at a scene file and that scene file
points back at the same data file, the engine gets stuck trying to load both
at once. It either freezes, silently leaves fields empty, or errors out. The
fix is to never store the "back-pointing" link as a real reference — derive it
from a naming rule or a string path so only one direction is hard-wired.

**Symptom.** A `.tres` ext_resources a `PackedScene` that, in turn,
ext_resources the same `.tres`. The engine attempts to resolve the cycle and
either hangs at load, returns a partially-initialised Resource (fields are
null when they shouldn't be), or fails with an obscure cycle error. Pure
GDScript script-level / `preload()`-chain cycles were fixed in 4.3
([#70985](https://github.com/godotengine/godot/issues/70985), PR
[#93346](https://github.com/godotengine/godot/pull/93346)) — the
`.tres → .tscn → .tres` *resource* form is the one that's still live.

**Repro.** An `ItemDef.tres` carries `@export var pickup_scene: PackedScene`,
and `pickup.tscn` ext_resources `ItemDef.tres` for its data. Loading either
end can resolve to a partial Resource.

**Fix.** Carry the inverse direction as a **String path**, or — better —
derive it by **convention** from a stable key (see [`../rules/dod.md`](../rules/dod.md)
D7a, "convention-derived dispatch"):

```gdscript
# Good: dispatch is a function of the enum, not a stored back-reference.
static func _scene_basename(id: Id) -> String:
    if id == Id.POTION: return "potion"
    elif id == Id.SWORD_GRIP: return "sword_grip"
    ...
    else: return ""   # boot validate catches missing arms
```

The `.tres` stays a leaf in the dependency graph; the `.tscn` keeps its
forward ref to the data. Boot-validate confirms the file exists; runtime
lookup is a single `load()`. See also [`../rules/resource-loading.md`](../rules/resource-loading.md)
for the broader `preload` / `load` rule of thumb, and **D11** for why a
parallel "scenes" registry mirroring the data registry is a coupling smell,
not a split.

**Issue / status.** Script-level / `preload()`-chain cycles were fixed in 4.3
([#70985](https://github.com/godotengine/godot/issues/70985), PR
[#93346](https://github.com/godotengine/godot/pull/93346)) — and
[#98551](https://github.com/godotengine/godot/issues/98551) ("Preloading
resources with cyclic dependencies fail") was **closed as a duplicate of
#70985**, so despite its name it documents that script-chain form, not this
one. The `.tres → .tscn → .tres` **resource-level form is still live**, tracked
among the open cyclic-dependency issues
([#80877](https://github.com/godotengine/godot/issues/80877) tracker;
[#109771](https://github.com/godotengine/godot/issues/109771), 4.5,
`@export PackedScene` cross-reference). **Re-tested on
Godot 4.8.dev** (`tests/repro_cycle_proj/`): a real `thing.tres → thing.tscn →
thing.tres` cycle does **not deadlock** (the 4.3 fix prevents the hang), but it
still **partial-loads** — loading `thing.tres` resolves its `scene`, yet
instantiating that scene yields a `def` back-reference of `null`, and the loader
logs `[ext_resource] referenced non-existent resource at: res://thing.tres` while
resolving the cycle. So the failure mode on 4.8.dev is a *silent null field* (and a
log error), not a freeze — which is arguably worse, because it sails past a quick
smoke test. The fix is unchanged: keep `.tres` a leaf — carry the inverse edge as a
convention-derived path, never a `PackedScene` ext_resource on a `.tres` the
`.tscn` already references. Lint flag: **C17**.

---

## 1h. Lock class-shared containers with `.make_read_only()`

**In plain terms:** for tables that *everyone* in the program reads, ask the
engine to lock them after you finish filling them in. Any later attempt to
change one will fail loudly with an error, instead of quietly corrupting the
table for every other reader.

The `static var` form admits the C2 shared-mutability bug. `.make_read_only()`
is the engine's enforcement layer: subsequent mutations raise `"Array is in
read-only state"`; reads work; the call is idempotent (`.is_read_only()` to
guard).

```gdscript
static var ALL: Array[ItemDef] = [null, preload("res://resources/items/potion.tres"), ...]

func _ready() -> void:
    _validate()
    if not ALL.is_read_only():
        ALL.make_read_only()
```

**Limit: shallow.** The freeze applies to the top-level container only. Nested
`Array` / `Dictionary` entries need their own `.make_read_only()` call. And
`Resource` has no freeze API at all (`Object.set_read_only` is unimplemented)
— `ALL[1].max_stack = 99` still mutates the singleton preload. At the
Resource-instance layer, immutability is a code-review convention, not an
engine guarantee.

**Lint flag: C2a.** No upstream issue — this is the prescribed workaround.

---

## Further live criticals — condensed

Live on 4.8.dev, shorter repros:

- **C13** — `Node.new()` without a parent leaks; pair every bare `.new()`
  with an owner or `queue_free`. No issue number — pattern, not a bug. *4.8.dev:
  confirmed — 2000 unparented `Node.new()` with refs dropped leaked exactly 2000
  objects; the same loop with `n.free()` leaked 0 (`repro_node_leak.gd`). Node is
  not reference-counted, so dropping the var is not enough.*
- **C14** — `range(n)` typed as `Array[int]` is actually untyped.
  [#72627](https://github.com/godotengine/godot/issues/72627) (canonical; the
  range-specific report
  [#110659](https://github.com/godotengine/godot/issues/110659) was closed as its
  duplicate). **Live** —
  *4.8.dev: confirmed, `range()`'s element type is untyped
  (`repro_typed_collections.gd` → C14).*
- **C15** — typed `Dictionary` + `Packed*` value type misbehaves; dup of
  [#88753](https://github.com/godotengine/godot/issues/88753).
  [#116947](https://github.com/godotengine/godot/issues/116947). **Live** —
  *but its parent #88753 (C1) no longer reproduces on 4.8.dev, so re-check on your
  target.*
- **C16** — `static var` inherited by subclass is not actually shared the
  way you'd expect. [#87629](https://github.com/godotengine/godot/issues/87629).
  **Live** — *4.8.dev observed: a subclass reads the base's `static var` as
  shared (set `Base.v` → `Derived.v` sees it); validate the exact divergence on
  your target.*

---

---
## Fixed in a known version — drop the workaround past your min Godot

These reproduced on an older Godot but are fixed in the version noted. Keep the
workaround only if your project's minimum predates the fix; otherwise drop it.
The full re-test verdicts are in the version-status table below.

- **C1** — `const Packed*Array` reported byte-count size and read 0.0. [#88753](https://github.com/godotengine/godot/issues/88753). **Not reproduced on 4.8.dev** (size correct; the nested-constructor form is now a parse error). Use `var`/`static var`, never `const`, if your min Godot predates the fix; the S6b style point — init a `Packed*Array` with a bare literal, not a constructor wrapper — holds regardless.
- **C2** — `const` `Array`/`Dictionary` was a shared mutable reference. [#61274](https://github.com/godotengine/godot/issues/61274). **Fixed on 4.8.dev** — a `const` container is now read-only; mutating it raises instead of silently corrupting the shared store. Discipline unchanged: never mutate a `const` container, `.duplicate()` first. (For class-shared `static var` tables the `.make_read_only()` lock — C2a above — is the live enforcement.)
- **C4** — `Array[Base]` covariance under `Array[Derived]` assignment.
  [#83876](https://github.com/godotengine/godot/issues/83876). *4.8.dev: typed
  arrays are **invariant**. A direct `var b: Array[Base] = derived_arr` is a
  **compile error** ("Cannot assign a value of type Array[Der] to … Array[Base]"),
  so the failure is loud at parse time, not a silent bug. Element covariance works
  (`Array[Base].append(Der)`), and `.assign()` does a checked element-wise copy —
  that's the conversion path (`repro_c4_covariance.gd`).*
- **C6** — coroutine resumed after `queue_free`. Fixed ~4.7.
  [#93608](https://github.com/godotengine/godot/issues/93608). *4.8.dev: the crash
  is gone, but the coroutine is **silently dropped** — it does NOT resume to
  completion. The repro proves this by writing to a `RefCounted` the caller still
  holds: `resumed` stays `false` (`tests/repro_async_proj/`). So "fixed" means "no
  longer crashes," not "runs to the end" — don't rely on a coroutine finishing if
  its owning node may be freed mid-`await`.*
- **C10** — `super()` in `_init` skipped. Fixed in 4.2.
  [#76938](https://github.com/godotengine/godot/issues/76938). *4.8.dev: confirmed
  fixed — `super()` runs the base ctor (`repro_lifecycle.gd` → C10).*
- **H8** — freed-Node truthiness / `== null` lied. [#59816](https://github.com/godotengine/godot/issues/59816). **Fixed 4.4** (≤4.3 still lie). `is_instance_valid(freed)` is `false` — use it as belt-and-suspenders on 4.4+ (S9).
- **H12** — `@export var` of a Resource type defaulted to `null` on load. [#110394](https://github.com/godotengine/godot/issues/110394). **Fixed 4.6.** A boot validator that errors on a still-null `@export` stays the right discipline.
- **M9** — `Resource.duplicate(true)` skipped nested `Array`s. [#74918](https://github.com/godotengine/godot/issues/74918). **Fixed 4.5** via `duplicate_deep()`.
- **P9** — Lua-style `d.key` dict access was ~2× slower than `d["key"]`. [#68834](https://github.com/godotengine/godot/issues/68834). **Fixed 4.4** — gap closed (1.01×); bracket access still preferred for type-clarity.

---
## Version-status summary

**In plain terms:** a one-glance table. Find the bug, check whether the Godot
version you're targeting already includes the fix, and decide whether you
still need the workaround.

The fast-path. If your project's minimum Godot is past the fix-version,
drop the workaround; otherwise, keep it.

"Status" is the issue-tracker verdict verified 2026-06. "4.8.dev" is what the
repro actually did on `custom_build.fd98f8452` — blank where we didn't re-run it
(it needs a release export, a frame loop, or project resources). Where the two
disagree, trust the empirical column **for that build only**.

| Flag | Bug | Issue | Status (2026-06) | Re-tested 4.8.dev |
|---|---|---|---|---|
| C1 | `const Packed*Array` corruption | [#88753](https://github.com/godotengine/godot/issues/88753) | **Live** | **Not reproduced** (size correct; nested-ctor form now a parse error) |
| C2 | `const` arrays/dicts shared & mutable | [#61274](https://github.com/godotengine/godot/issues/61274) | **Live** (partial) | **Fixed** — `const` is read-only, mutation raises |
| C2a | `.make_read_only()` on `static var` | — | Prescribed pattern | **Works** (`is_read_only()` true after) |
| C3 | typed `.filter()`/`.map()` returns untyped | [#72566](https://github.com/godotengine/godot/issues/72566) | **Live** | **Split**: `.filter()` typed (fixed), `.map()` still untyped |
| C4 | `Array[T]` covariance | [#83876](https://github.com/godotengine/godot/issues/83876) | **Uncertain** — re-test | **Invariant** — direct `Array[Base]=Array[Der]` is a compile error; element-covariance + `assign()` work |
| C5 | `await` on freed object | [#72629](https://github.com/godotengine/godot/issues/72629) | **By design** — validity check is the pattern | **Confirmed** — `is_instance_valid` false after await; guard works |
| C6 | coroutine after `queue_free` | [#93608](https://github.com/godotengine/godot/issues/93608) | **Fixed ~4.7** | No crash, but coroutine **silently dropped** (does not resume to completion) |
| C7 | `RefCounted` circular leak | [#7038](https://github.com/godotengine/godot/issues/7038) | **Live** | **Live** — leaked ~4000 objs / 2000 cycles |
| C8 | freed-id reuse | [#32383](https://github.com/godotengine/godot/issues/32383) | **By design** — validity + type check | **Confirmed** — `instance_from_id(freed)` → null |
| C10 | `super()` in `_init` | [#76938](https://github.com/godotengine/godot/issues/76938) | **Fixed 4.2** | **Confirmed fixed** — `super()` runs base ctor |
| C11 | `sort_custom` strict `<` | [#58878](https://github.com/godotengine/godot/issues/58878) | **Live** | Not stable by contract (this input held order) |
| C12 | `assert()` stripped in release | — | **By design** | **Confirmed** — assert body runs in debug, stripped in release (ran=false) |
| C13 | `Node.new()` leak | — | Pattern | **Confirmed** — 2000 unparented `Node.new()` leaked 2000; `free()` → 0 |
| C14 | `range(n)` typed as `Array[int]` | [#72627](https://github.com/godotengine/godot/issues/72627) (dup [#110659](https://github.com/godotengine/godot/issues/110659)) | **Live** | **Live** — `range()` element type is untyped |
| C15 | typed Dict + `Packed*` value | [#116947](https://github.com/godotengine/godot/issues/116947) | **Live** (dup of #88753) | — (C1 fixed → re-check on target) |
| C16 | `static var` inheritance | [#87629](https://github.com/godotengine/godot/issues/87629) | **Live** | Observed: subclass shares the base's `static var` |
| C17 | `.tres ↔ .tscn` resource cycle | [#80877](https://github.com/godotengine/godot/issues/80877) / [#109771](https://github.com/godotengine/godot/issues/109771) | **Live** (script/preload form fixed 4.3 — #98551 was its dup) | **Live** — no hang, but partial-load: back-ref null + ext_resource error |
| H8 | freed-Node truthiness lies | [#59816](https://github.com/godotengine/godot/issues/59816) | **Fixed 4.4** (≤4.3 still lie) | **Confirmed fixed** — `is_instance_valid(freed)`=false |
| H12 | `@export` Resource null on load | [#110394](https://github.com/godotengine/godot/issues/110394) | **Fixed 4.6** | **Confirmed fixed** — `@export` Resource survives scene load |
| M9 | `Resource.duplicate(true)` skips Array | [#74918](https://github.com/godotengine/godot/issues/74918) | **Fixed 4.5** via `duplicate_deep()` | **Confirmed fixed** — deep-dup, original unaffected |
| P9 | Lua-style dict-access perf | [#68834](https://github.com/godotengine/godot/issues/68834) | **Fixed 4.4** | **Confirmed fixed** — `d.key` vs `d["key"]` = 1.01× (gap closed) |

Keep every warning your project's minimum Godot predates. The
discipline of this Bible is the same as Part III's: workarounds are
*real cost*, and the moment a fix lands you can pay that cost back.
