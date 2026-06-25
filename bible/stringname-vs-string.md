# StringName vs String: use StringName for identifiers

A `StringName` is an **interned** string — the engine keeps one shared copy, so two
`StringName`s with the same text share an id. That makes `==` an id compare instead
of a character walk, and a dictionary lookup hash a cached id. Use `StringName`
(`&"x"`) for **identifiers** — names you compare, look up, or hand to an engine
API — and plain `String` for **text** you build, manipulate, or display.

**In plain terms:** if a string is a *label* you keep checking ("is this the
`alive` group?", "play the `walk` animation"), make it a `StringName` with the `&`
prefix — it's the type the engine wants and it compares faster. If a string is
*content* you're building or showing to the player, keep it a `String`.

---

## Measured (4.8.dev, `bench_stringname.gd`)

Best-of-7, N=1,000,000:

| Op | StringName | String | String cost |
|---|---|---|---|
| `==` (equal 36-char ids) | 15.2 ms | 18.9 ms | **1.2×** |
| `dict[key]` lookup | 32.8 ms | 38.4 ms | **1.2×** |
| intern `StringName(runtime_str)` | 45.3 ms / 1M | — | the price you pay once |

**The honest read: the speed edge is modest (~1.2×), not dramatic** — GDScript's
`String` compare is already decent, and it grows with identifier length and call
frequency. So the *primary* reason to prefer `StringName` is **not** raw speed:

1. **Engine APIs take `StringName`.** Groups, input actions, signals, node/anim/
   theme names, `Object.call`/`get`/`set` — passing a bare `String` forces a
   per-call conversion (P12a). The type *is* the contract.
2. **Interning makes equality semantic, not textual** — and it scales: the win is
   bigger for long ids and in the engine's own C++ (groups, signal dispatch are
   `StringName` natively).
3. **A typo is a different id**, caught the same way every other identifier typo is.

And the cost to respect: **interning a runtime `String` is the expensive line**
(45 ms/1M). Do it **once at a boundary**, never per frame — `StringName(s)` in a
hot loop is worse than just using the `String`.

## When each

| Use `StringName` (`&"x"`) | Use `String` |
|---|---|
| group names — `add_to_group(&"alive")`, `is_in_group(&"alive")` | text you build — concat, `substr`, `format`, `split` |
| input actions — `Input.is_action_pressed(&"jump")` | file paths — `load("res://...")`, `FileAccess.open` (these take `String`) |
| signal / method / property names — `connect`, `call`, `get`, `has_method` | display / UI text, user input |
| animation / theme / node names — `play(&"walk")`, `add_theme_*_override` | regex subjects, CSV fields, anything parsed |
| dict keys for fixed/hot lookups — quest flags, stat fields (`&"damage"`) | a one-off string compared once |
| any fixed identifier compared repeatedly | a string assembled at runtime from parts |

This is the same line Part IV **D10/D10a** draws for *closed enum vs StringName*:
prefer an **`enum`** for a fixed closed set you own (compile-time exhaustive, an
int compare); reach for `StringName` when the value crosses an engine API that
demands it or genuinely needs string-like identity. Enum > StringName > String,
in that order of preference for an identifier.

## Two gotchas

- **Literal syntax matters (P12a).** Write `&"jump"`, not `"jump"`, where the API
  wants a `StringName` — a bare literal is a `String` that gets converted on every
  call. `.tscn` hand-edits: `&"id"`.
- **`StringName` is not `String` — same method names, different signatures
  (P12b).** `StringName.begins_with(text: String)` takes a `String`;
  `StringName.substr` *returns* a `String`. Wrap explicitly at the boundary:
  `var id: StringName = StringName(some_name.substr(6))`. Check
  `docs <Class>.<method>` for the real signature rather than assuming.

## Don't over-convert

The trap on the other side: building a `StringName` from a runtime `String` every
frame (the 45 ms/1M line above) to "be fast" is slower than just comparing the
`String`. `StringName` pays off for **fixed identifiers known at author time**
(the `&"..."` literals), not for runtime-assembled text. Intern at the boundary
(load, parse, first use), cache the result, and compare the cached `StringName`
thereafter.

## Run it

```bash
godot --headless --script tests/bench_stringname.gd
```
