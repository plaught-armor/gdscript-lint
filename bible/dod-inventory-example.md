# DOD by example: an inventory (D11 — no mirror registries)

A third worked subsystem (after [combat](dod-by-example.md) and
[perception](dod-perception-example.md)), built around **D11**: two parallel
tables keyed by the same enum aren't a "split" — they're one fact stored twice.
Runnable: [`tests/example_dod_inventory_proj/`](../tests/example_dod_inventory_proj/),
verified on 4.8.dev.

**In plain terms:** there's one list of item definitions. The icon for each item
is figured out from its name (not stored in a second list that has to stay lined
up), and "what you're carrying" is a dictionary where *being a key means you have
it* — take the last one and the key disappears.

---

## The D11 smell: mirror registries

The naive registry grows a parallel array every time a new per-item asset
appears — one for defs, one for icons, one for pickup scenes — each keyed by the
same `enum Id`, each that must stay length-aligned:

```gdscript
# Bad — three arrays that must agree, guarded by a parity test.
enum Id { POTION, ETHER, SWORD, SHIELD }
static var DEFS: Array[InvItemDef]   = [ ... ]   # the data
static var ICONS: Array[Texture2D]   = [ ... ]   # mirror #1
static var SCENES: Array[PackedScene]= [ ... ]   # mirror #2

# The giveaway — a test whose only job is to assert two lengths match:
assert(ICONS.size() == Id.size())
assert(SCENES.size() == Id.size())
```

Every new item edits three arrays in lockstep; forget one and the parity test
fails (if you're lucky) or an index silently returns the wrong asset (if you're
not). **The parity-asserting test is the smell** — it exists because the same
index space is encoded more than once.

## The fix: one table, fold or derive

Two ways out, both used here:

1. **Fold per-item constants into the def** (D1). `max_stack` is a *field* on
   `InvItemDef`, not a parallel `STACKS` array.
2. **Derive convention-keyed assets** (D7a). The icon path falls out of the
   def's name — no `ICONS` array to align:

```gdscript
static var defs: Array[InvItemDef] = [
	InvItemDef.new(&"potion", 99), InvItemDef.new(&"ether", 99),
	InvItemDef.new(&"sword", 1),   InvItemDef.new(&"shield", 1),
]
static func _static_init() -> void:        # C2a: lock the one table (shallow)
	if not defs.is_read_only(): defs.make_read_only()

static func icon_path(id: Id) -> String:   # D7a: derived, no mirror array
	if id == Id.POTION: return "res://icons/potion.png"
	if id == Id.SWORD:  return "res://icons/sword.png"
	...                                     # interned literals → allocation-free
	return ""                               # loud default; boot validate omitted
```

One table. No parity test, because there's nothing to keep aligned. (The icon
path is the canonical D7a form — `if/elif` returning interned string literals,
*not* a `"%s"`-formatted path, which would allocate per call.)

## Existence-based contents (D2)

"What you're carrying" is a `Dictionary[int, int]` (Id → count). Presence *is*
having the item; removing the last one **erases the key**, so there's no
`count == 0` zombie and `distinct()` is just the dict size:

```gdscript
var _counts: Dictionary[int, int] = {}     # presence == carried

func add(id: InvItemRegistry.Id, n: int) -> int:
	var cur: int = _counts.get(id, 0)
	var added: int = clampi(n, 0, InvItemRegistry.get_def(id).max_stack - cur)
	if added > 0: _counts[id] = cur + added
	return n - added                        # leftover that didn't fit the stack

func remove(id: InvItemRegistry.Id, n: int) -> int:
	var cur: int = _counts.get(id, 0)
	var taken: int = clampi(n, 0, cur)
	if cur - taken > 0: _counts[id] = cur - taken
	elif cur > 0: _counts.erase(id)         # last one gone → key drops
	return taken
```

`add` reads `max_stack` straight off the folded field — the very thing a mirror
`STACKS` array would have held, now in one place.

## Verified output

```
[demo] add 120 potion → kept 99, leftover 21        # folded max_stack caps the stack
[demo] add 2nd sword → count 1, leftover 1          # sword max_stack is 1
[demo] distinct item kinds carried: 3
[demo] removed all ether → has ether? false, distinct now 2   # key erased, not zombie-0
[demo] icon(potion) = res://icons/potion.png        # D7a derived, no ICONS array
[demo] icon(sword) = res://icons/sword.png
```

## What each rule bought

| Rule | Mirror design | Here | Win |
|---|---|---|---|
| D11 | `DEFS` + `ICONS` + `SCENES` + parity tests | one `defs` table | nothing to keep aligned; parity test gone |
| D1 | per-item constants in a `STACKS` array | `max_stack` field on `InvItemDef` | one place to read/edit a stack limit |
| D7a | `ICONS[id]` parallel array | `icon_path(id)` derived from name | new item needs no second-array edit |
| D2 | `count == 0` sentinels | erase the key | `distinct()` = dict size; no zombie entries |
| C2a | `const` arrays (C1/C2 bug) | `static var` + `make_read_only` | shared table can't be mutated |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_inventory_proj --import   # once
"$GODOT" --headless --path tests/example_dod_inventory_proj
```
