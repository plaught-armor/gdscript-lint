---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/project.godot"
---

# GDScript Rules — Index

**Canonical knowledge** — teaching prose + rationale per rule. These files = source of truth; automated linter/reviewer enforces subset as terse flag conditions citing back here. `dod.md` = full data-oriented-design deep-dive (rules D1-D11, incl. D2a/D2b/D5a/D7a/D7b/D10a, plus the dispatch-cost table and perf rules P18-P22).

| File | When to load |
|---|---|
| [`architecture.md`](architecture.md) | Cross-project skeleton — dir layout, canonical autoloads, naming-by-kind, subsystem shape templates (Registry, HUD facade, Manager), decision rubric. Default ref for "where should X live?". |
| [`engine-bugs.md`](engine-bugs.md) | Crash, leak, "compiles but wrong at runtime", or any `const`/typed-collection puzzle. |
| [`type-async.md`](type-async.md) | Typing rules, lambdas, `await`/coroutine traps, signal timeouts, Node-name shadowing. |
| [`style.md`](style.md) | Boot/init validation (incl. editor-gated validators), `StringName`/`NodePath` literal matching, `.is_empty()`, typed containers, duck-dispatch ban, `@export` rules, scene inheritance, authoring-equivalence test. |
| [`dod.md`](dod.md) | Data shape: POD records, existence-based processing, ID refs, hot/cold split, transforms, condition tables (incl. convention-derived dispatch + value-only `match`→`if/elif`), batched ticks, dispatch costs, inline perf checklist, enum-at-API-boundary, mirror-registry anti-pattern. |
| [`resource-loading.md`](resource-loading.md) | `preload` vs `load` vs threaded loading, cache modes + lifetime, UID files, "don't roll your own cache", `.tres ↔ .tscn` cycle avoidance. |
| [`persistence.md`](persistence.md) | Save/load runtime state — serialization choice + **Object-deserialization RCE gate**, compression (zstd, measured), atomic write, save migration / version byte. The *write path*; record *shape* in `dod.md` (D1/D3/D4/D6). |

Some flag IDs (e.g. C13, H7, M4, S2, P6) referenced inline condensed — one-line summary at point of reference = the rule.

Project-local rule overrides take precedence over these defaults.