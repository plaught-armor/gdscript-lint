# Part VI — Resource loading

When `.tres`/`.tscn`/`Resource` load, cache, and free — and when to reach for
`preload` vs `load` vs threaded loading.

Draws from [`../rules/resource-loading.md`](../rules/resource-loading.md).

## Outline
- preload constants, load variables, thread-load levels
- cache semantics (strong-refcount) + cache modes
- don't roll your own cache; don't `exists()` after a boot validate
- editor-gate expensive validators
- no bidirectional `.tres ↔ .tscn` ext_resource (cycle)
- UID sidecar files — commit them

*Status: outline.*
