# DOD by example: where membership lives (D2b — ration groups like autoloads)

A worked companion to [the perception example](ex-perception.md). Perception
showed **state as membership, not a flag** (D2). This one asks the next question
D2 leaves open: *which container holds the membership, and at what scope?* The
answer is **D2b** — a Godot group is a tree-global namespace, so ration it like an
autoload; when one owner sees every add and remove, that owner holds the set
directly. Runnable:
[`tests/example_dod_membership_proj/`](../../tests/example_dod_membership_proj/),
verified on 4.8.dev.

**In plain terms:** two rooms each have some enemies. "How many are alive in room
0?" should be a one-line answer the room already knows — not a search of the whole
game for everything tagged `alive` and then a filter by room. Groups are a global
bulletin board; don't pin a thing there when one room already owns it.

---

## The naive shape

The reflex after learning D2 is "membership → group," everywhere:

```gdscript
# Naive — reflex "membership → group" for a set one owner already sees.
class_name Enemy extends Node
func _ready() -> void: add_to_group(&"alive")     # the reflex
func _die() -> void:   remove_from_group(&"alive")

# somewhere else, the question "who's alive in room 0?":
var here: Array[Node] = []
for n: Node in get_tree().get_nodes_in_group(&"alive"):   # whole-tree sweep,
    if n.get_parent() == room0:                            # fresh alloc, then
        here.append(n)                                     # filter by room
```

Three things are wrong, and none of them is speed:

- **No scope.** `&"alive"` is one set on the whole `SceneTree`
  (`HashMap<StringName, Group>`, process-global). It can't mean "alive *in this
  room*" — every room's enemies land in the same bucket. To scope it you mint
  `&"room0_alive"`, `&"room1_alive"` … a namespace you now manage by string
  convention. That's the autoload-name hazard (4h): a global identifier
  two systems can collide on.
- **No locality.** `get_nodes_in_group` returns nodes scattered across the tree
  in unspecified order, freshly allocated each call (D2a). There's no contiguous
  array to walk.
- **A second source of truth you didn't need.** The room *already* spawns and
  kills these enemies — it sees every transition. The group is a second ledger of
  a fact the room already holds, kept in sync by remembering two `*_from_group`
  calls.

## The data-oriented shape

The owner that sees every add and remove holds the set **directly**, typed and
scoped:

```gdscript
class_name Room extends Node
var _alive: Array[Enemy] = []          # owner-held membership (D2b), this room only

func spawn(enemy_id: int) -> Enemy:
    var e: Enemy = Enemy.new()
    e.id = enemy_id
    add_child(e)
    _alive.append(e)                   # the owner sees the add — no group
    return e

func kill(enemy_id: int) -> void:
    for i: int in _alive.size():
        if _alive[i].id == enemy_id:
            _alive[i].queue_free()
            _alive[i] = _alive[_alive.size() - 1]   # swap-back: last over the hole
            _alive.resize(_alive.size() - 1)        # drop the tail — O(1), no shift
            return

func alive_count() -> int: return _alive.size()   # scoped, O(1), no global name
```

"Alive in room 0" is `room0.alive_count()` — O(1), no tree sweep, no global string,
no second ledger. The array is contiguous and typed (`Array[Enemy]`), the shape
4d (split by access pattern) and 4g (the manager's cached `_alive`) already land
on.

The removal is **swap-back**, not `remove_at`: an alive-set is *unordered*
(membership, not sequence), so overwrite the dead slot with the last element and
drop the tail — O(1), no element shift. `remove_at(i)` would shift every element
after `i` down one (O(n)); reserve that for sets whose order is load-bearing. This
is the [removing-dead-entities](note-removing-dead-entities.md) note's "swap-back
for a single removal" — a real project packages it as the `SwapBackArray` addon;
the example inlines it to stay dependency-free.

### The other half: when a group *is* right

D2b is not "avoid groups." It's "groups are the global tool — spend them on global
membership." The example keeps a `Door` in each room tagged `&"interactable"`:

```gdscript
class_name Door extends Node
func _ready() -> void: add_to_group(&"interactable")
# the player's interact raycast, owning nothing, queries the whole tree:
var hits: Array[Node] = get_tree().get_nodes_in_group(&"interactable")
```

This is the autoload-shaped case the group is *for*: membership that is **tree-wide**
(any room, any object), queried by a **decoupled** consumer (the raycast holds no
reference to any door), with **runtime-variable** membership. No single system owns
"the set of interactable things," so no owner can hold the array — the global
registry is exactly the right home.

The decision, in one table:

| Membership is… | Container | Why |
|---|---|---|
| tree-wide, decoupled consumers, no single owner | group `&"tag"` | engine's global registry; O(1) membership (D2a) |
| owned by one manager / room that sees every add + remove | that owner's typed `Array[T]` | locality, typed, save-friendly, no global name |
| per-entity data on a subset | `Dictionary[int, T]` keyed by id | answers "what data", not just "in the set" |

## The run

`godot --headless --path tests/example_dod_membership_proj` (import once first):

```
[D2b] owner-held array (good) — scoped, O(1), no global name:
[D2b]   room 0 alive=3 ids=[1, 2, 3]
[D2b]   room 1 alive=2 ids=[4, 5]
[D2b] after room0.kill(2) — local update only:
[D2b]   room 0 alive=2 ids=[1, 3]
[D2b]   room 1 alive=2 ids=[4, 5]
[D2b] tree-global &"alive" (anti-pattern) — both rooms collapse:
[D2b]   total=4 across the whole tree; "alive in room 0" is
[D2b]   unanswerable without minting &"room0_alive" — the smell.
[D2b] &"interactable" (legit group) — tree-wide, owner-less query:
[D2b]   a player raycast finds 2 interactables, owning none. THIS is
[D2b]   what the global registry is for.
```

Read it top to bottom: each room answers `alive_count()` for **its own** scope;
`room0.kill(2)` updates room 0's array and touches nothing else; the tree-global
`&"alive"` collapses both rooms into one count of 4 with no way back to "room 0";
and `&"interactable"` — the one genuinely global, owner-less set — is where a group
earns its keep.

## Variants & use-cases

- **Save scope.** The owner-held array serializes per-room (`room_state[i].alive`)
  — a relational `SaveSlot` field (4d). A tree-global group has no natural per-room
  partition to write; you'd reconstruct scope from node paths at save time.
- **Streaming / unloading.** Free a room subtree and its `_alive` goes with it —
  no dangling group entries to scrub. With one global `&"alive"`, unloading room 0
  has to remember to pull every member out, or the count lies.
- **Co-op / multiple arenas.** Two simultaneous arenas each own their set with no
  name collision. The group form forces `&"arena{n}_alive"` — re-deriving, as a
  string, the ownership the array gave you for free.
- **Genuinely global tags stay groups.** `&"interactable"`, `&"save_participants"`,
  `&"hazard"` — swept by a system that owns none of the members. Don't "promote"
  these to owner arrays; there's no single owner, so the group is correct.
- **One owner, many readers → owner array + a signal.** If decoupled systems must
  *react* to room membership changes (a HUD counter), keep the array on the room
  and emit a signal on add/remove (P18) — decoupling is the signal's job, not the
  group's.

The throughline with the rest of Part IV: **membership is the principle (D2);
the container is a separate decision (D2b).** Pick it by ownership and scope, not
by reflex — and a group, like an autoload, is a global resource you spend
deliberately.
