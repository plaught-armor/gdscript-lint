# Part I — Engine bugs

Code that compiles fine and crashes, leaks, or silently corrupts at runtime.
Each entry: symptom → minimal repro → fix → Godot issue # → **version status**
(live, or fixed-in-X so you can drop the workaround).

Draws from [`../rules/engine-bugs.md`](../rules/engine-bugs.md).

## Outline
- `const Packed*Array` reports byte-count size, reads 0.0 (#88753) — never `const`
- `const` arrays/dicts are shared mutable refs (#61274); `.make_read_only()`
- typed `.filter()`/`.map()` return untyped Array (#72566) — `.assign()`
- `await` on a freed object; freed instance-id reuse — validity + type check
- RefCounted circular refs leak silently — weakref or entity IDs
- `sort_custom` must be strict `<`; `assert()` stripped in release
- `.tres ↔ .tscn` preload cycles (#98551)
- version-status table: which are still live, which fixed in which release

*Status: outline. Expand each to full repro + fix.*
