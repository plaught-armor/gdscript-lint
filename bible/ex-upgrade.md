# DOD by example: a stat/upgrade system (+ the authoring-equivalence test)

Worked example #7. A stat upgrade is a **pure transform** `(base, part) → new
stats`, and the standout pattern here is the **authoring-equivalence test**: when
a generator (`apply_part`) and a hand-authored output (`sword_mk2.tres`) both
exist, a test locks them equal so a designer bumping one side without the other
**fails loud**. Runnable:
[`tests/example_dod_upgrade_proj/`](../tests/example_dod_upgrade_proj/), verified
on 4.8.dev.

**In plain terms:** upgrading a weapon is just math on numbers — take the base
stats, add the upgrade's bonuses in a fixed order, get new stats. And because the
upgraded sword *also* exists as a hand-tuned file, a test checks the math and the
file still agree, so they can't silently drift apart.

---

## The shape

POD defs (D1), one pure transform (D6). The modifier **order is the system** —
flat add, then additive `%` (increased), then multiplicative `%` (more), the
Path-of-Exile pipeline:

```gdscript
static func apply_part(base: WeaponDef, part: WeaponPartDef) -> WeaponDef:
	var out: WeaponDef = WeaponDef.new()
	out.damage = (base.damage + part.flat_damage) \
		* (1.0 + part.increased_damage) \
		* (1.0 + part.more_damage)
	out.attack_speed = base.attack_speed + part.flat_attack_speed
	out.crit_chance = base.crit_chance
	return out
```

`(10 + 5) × 1.5 × 1.2 = 27`. Order matters: the additive `%` bucket sums *then*
multiplies, so the result is independent of the order parts were equipped.

## The authoring-equivalence test

`sword_mk2.tres` is hand-authored (designer-tunable, diffable). `apply_part(base,
grip)` is the generator. **Neither is canonical — they must agree.** The test
walks the field set and compares with a float tolerance:

```gdscript
const FIELDS: Array[StringName] = [&"damage", &"attack_speed", &"crit_chance"]
...
for f: StringName in FIELDS:
	if absf(computed.get(f) - authored.get(f)) > 0.0001:   # get(StringName), P12a
		drift = true   # a designer bumped one side without the other → fail loud
```

In production this is a GUT invariant; here it runs inline. The field list is
`StringName` (interned, typo-safe, the right type for `Object.get`).

## Verified output

```
[demo] base: dmg=10.00 spd=1.00
[demo] computed apply_part(base, grip): dmg=27.00 spd=1.20 crit=0.05
[demo] authored sword_mk2.tres:         dmg=27.00 spd=1.20 crit=0.05
[demo] authoring-equivalence: PASS (generator == authored)
```

Bump `sword_mk2.tres`'s damage to 28 without touching the grip part and the line
flips to `DRIFT — fails loud`. That's the point: the deltas in `WeaponPartDef`
stay visible and tunable, but the actual `.tres` is hand-diffable, and the two can
never silently disagree.

## What each rule bought

| Rule | Naive | Here | Win |
|---|---|---|---|
| D1 | stats+logic on a Node | POD `WeaponDef`/`WeaponPartDef` | tunable `.tres`, testable, no tree |
| D6 | `weapon.upgrade(part)` mutates self | `UpgradeSystem.apply_part` returns new | pure, order-independent, unit-testable |
| — | trust the generator | authoring-equivalence test | generator vs authored locked; drift fails loud |

---

## Variants & use-cases

### Modifier order — pick the pipeline

| Pipeline | When | Note |
|---|---|---|
| **flat → increased(+%) → more(×%)** (this example, PoE) | depth-driven ARPGs; "more" is scarce/gated, "increased" abundant | two `%` tiers create exponential build power |
| flat → additive% → one multiplicative bucket | RPGs not chasing PoE depth | same order-independence, flatter curve |
| **category buckets** (D3) — N additive buckets that multiply | themed scaling (Elite dmg, Elemental dmg as separate axes) | same math, content-named buckets |
| per-modifier explicit `Order` int (Kryzarel) | mod-friendly: new types slot between (Order=150) | order-as-data, no pipeline recompile |
| GAS ops: Add/Multiply/Divide/**Override** | UE / multiplayer | Override is the one home-rolled systems forget (immunity = HP×0) |

The invariant across all of them: **modifiers apply as a set, so the final value
is independent of equip order** — without it, two +100% mods can give +400%
instead of +200% ([Kryzarel](https://medium.com/@kryzarel/character-stats-attributes-in-unity-pt-1-70f90ade9788),
[RefresherTowel](https://refreshertowelgames.wordpress.com/2024/02/17/how-to-comfortably-deal-with-modifiable-stats/),
[vhpg PoE more vs increased](https://www.vhpg.com/poe-more-vs-increased/)).

### Stacking, sources, duration

- **Source-tagged modifiers** + `remove_all_from_source(obj)` — unequip an item,
  drop all its modifiers in bulk. Each modifier back-refs its source.
- **Duration policy: instant / duration / infinite** (GAS) maps cleanly to
  consumable / timed buff / passive-aura.
- **Stacking rules**: same-source → take higher (don't sum); cross-source/typed →
  stack; stack-count + per-stack timers for DoTs.
- **Snapshot vs dynamic** is a *design* lever, not perf: snapshot stats at cast
  (PoE DoTs) vs recompute per tick (buff drops → damage drops). Pick by intent.

### Recompute strategy

| Strategy | When | Source |
|---|---|---|
| recompute every read | cold-path stats, rare reads | simplest |
| recompute-on-change (cache final) | many reads per write (damage read 60×/s, gear-swap rare) | eager |
| **dirty-flag cache** | writes *batch* (equip 5 items → 1 recompute on next read) | [GPP Dirty Flag](https://gameprogrammingpatterns.com/dirty-flag.html) — **no win if you read after every write** |
| incremental "pay as you go" | cheap linear deltas, always-fresh | breaks on a multiplicative stage |
| dependency DAG resolve | stats derive from stats (STR→HP) | only worth it for interdependent networks |

The DOD shape underneath all of them: **modifiers are POD records in a list; the
final is a pure transform `(base, modifiers[]) → value`** — no methods on
modifiers.

### Data layout (and the shared-`.tres` footgun)

- **Authored `.tres` template + runtime state in a separate `var`** is the clean
  default — designer tunes the `.tres`, gameplay never mutates it.
- **Save IDs + selected-upgrade ids, not the computed Resource** — recompute final
  stats at load; lets designers rebalance post-launch without breaking saves.
- ⚠️ **Shared-`.tres` mutation**: assigning one `WeaponDef.tres` to N weapons
  shares the ref — mutating one mutates all. `duplicate()` per-instance when an
  item has per-instance state (durability/enchantments); pair `make_read_only()`
  (C2a) on registry tables.

### Use-case sheet

| Use-case | Recompute | Stacking | Save shape |
|---|---|---|---|
| RPG base stats (STR/DEX/INT) | dirty-flag (rare writes, many reads) | source-tagged + typed buckets | ids, not derived values |
| weapon upgrade tree (mk1→2→3) | recompute-on-change (upgrade is rare) | single linear chain | selected node ids; recompute at load |
| buff/debuff timers | snapshot or per-tick (design call) | per-stack expiry, highest-wins | `[aura_id, remaining, stacks, source]` |
| equipment set bonuses | recompute on equip | activate at count ≥ threshold | set id + piece ids |
| consumables | instant policy (apply + consume) | often non-stacking / refresh | inventory count + active auras |

## Run it

```bash
GODOT=/path/to/godot
"$GODOT" --headless --path tests/example_dod_upgrade_proj --import   # once
"$GODOT" --headless --path tests/example_dod_upgrade_proj
```
