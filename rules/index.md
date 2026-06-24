# GDScript Rules — Index

**Canonical knowledge** — teaching prose + rationale for each rule. These files are the source of truth; an automated linter / reviewer enforces a subset of them as terse flag conditions that cite back here. `dod.md` is the full data-oriented-design deep-dive (rules D1-D11, incl. D2a/D7a/D10a).

| File | When to load |
|---|---|
| [`architecture.md`](architecture.md) | Cross-project skeleton — dir layout, canonical autoloads, naming-by-kind, subsystem shape templates (Registry, HUD facade, Manager), decision rubric. Default reference for "where should X live?". |
| [`engine-bugs.md`](engine-bugs.md) | Hitting a crash, leak, "compiles but wrong at runtime", or any `const`/typed-collection puzzle. |
| [`type-async.md`](type-async.md) | Typing rules, lambdas, `await`/coroutine traps, signal timeouts, Node-name shadowing. |
| [`style.md`](style.md) | Boot/init validation (incl. editor-gated validators), `StringName`/`NodePath` literal matching, `.is_empty()`, typed containers, duck-dispatch ban, `@export` rules, scene inheritance, authoring-equivalence test. |
| [`dod.md`](dod.md) | Data shape: POD records, existence-based processing, ID refs, hot/cold split, transforms, condition tables (incl. convention-derived dispatch + value-only `match`→`if/elif`), batched ticks, dispatch costs, inline perf checklist, enum-at-API-boundary, mirror-registry anti-pattern. |
| [`resource-loading.md`](resource-loading.md) | `preload` vs `load` vs threaded loading, cache modes + lifetime, UID files, "don't roll your own cache", `.tres ↔ .tscn` cycle avoidance. |

Some flag IDs (e.g. C13, H7, M4, S2, P6) are referenced inline in condensed form — the one-line summary at the point of reference is the rule.

Project-local rule overrides take precedence over these defaults.
