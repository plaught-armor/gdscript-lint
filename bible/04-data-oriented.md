# Part IV — Data-oriented design

Code transforms data; it doesn't model "things." POD records + pure transforms,
state as container membership, references by ID, schema by access pattern.

Draws from [`../rules/dod.md`](../rules/dod.md).

## Outline
- POD data, behavior as `static func` transforms on a systems layer
- existence-based processing: set/group membership over `bool` flags
- reference by integer ID, resolve + validity-check at use site
- split data by access pattern, not domain object; hot/cold split
- condition tables over branch chains; convention-derived dispatch
- value-only `match` → `if/elif` (the measured dispatch cost — Part III)
- batched homogeneous processing over per-Node ticks

*Status: outline.*
