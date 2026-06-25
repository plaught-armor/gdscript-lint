# The case for Data-Oriented Design (even in GDScript)

> A position piece, not a survey. Part VII lays the paradigms side by side and
> stays neutral; this argues one side. The claim: **default to data-oriented
> design in Godot — not because it's fast (in GDScript the speed win is real but
> muted), but because it's the cheapest path to correct, testable, engine-aligned
> code, and because it's where the engine pushes you anyway the moment you scale.**

## The default instinct is the expensive one

Open a blank script and the reflex is to model the noun: `class Enemy` with
health, position, an AI state, an inventory, a `take_damage()`, a `_die()`. One
class, one rocket. Mike Acton's framing of why that's the wrong reflex still
lands ([CppCon 2014](https://www.youtube.com/watch?v=rX0ItVEVjHc)): the three
lies are that **software is a platform**, that **code should model the world**,
and that **code matters more than data**. The `Enemy` class is all three at once
— it models a world-noun, treats the SceneTree as a free platform, and decides
the *shape of the data* (30 fields, one object, touched by five systems) as an
afterthought of the code.

Data-oriented design inverts the order: decide the data first, because **the
shape of the data determines what code is possible and how fast it runs.** Code
is the transform `(input data) → (output data)`, not a model of a thing.

## Concede the cache argument up front — then watch it not matter

The honest objection first, because pretending it away is how you lose the
argument: **DOD's headline win is cache locality, and GDScript barely has it.**
The interpreter boxes everything in Variants; the engine's own proposal admits
"classes are not lightweight… memory is all over the place so there is not much
cache locality"
([#7329](https://github.com/godotengine/godot-proposals/issues/7329)). The
struct-of-arrays cache magic that makes C++ DOD a 10× win lives in Godot's C++
servers, not your `.gd` files.

So if the only argument for DOD were raw speed, you could fairly shrug in
GDScript. It isn't. The cache win is the *least* portable reason. Here are the
four that survive the trip into a managed language — and three of them aren't
about speed at all.

## 1. It's the cheapest correctness, at zero entities

This is the argument that doesn't depend on scale, profiling, or the
interpreter. DOD eliminates whole *bug classes* by construction:

- **Existence-based processing** — state is membership in a container, not a flag
  on every object. `alive` is a group, not `is_dead: bool`. There is no flag to
  desync from reality, because the flag *is* reality: iteration over the alive
  set is correct by definition (Part IV **D2**). The bool version has two sources
  of truth and they drift; the set version has one.
- **Reference by ID, not pointer** — a stale pointer to a freed node is a Godot
  footgun with a CVE-shaped history (freed-id reuse,
  [#32383](https://github.com/godotengine/godot/issues/32383)). An integer ID
  resolved at the use site returns a live object or `null`, never a wrong-type
  live one (Part IV **D3**, Part I **C8**). The bug can't happen.
- **Transforms over methods** — `CombatSystem.resolve(hit, target)` is a pure
  function you can unit-test with two plain objects and no SceneTree. `hit.apply()`
  drags the tree, the node lifecycle, and the save format into every test (Part
  IV **D6**).

None of this is a performance claim. A turn-based card game with nine entities
gets every one of these wins. **DOD is correct-by-construction before it is
fast.** That's the argument to lead with, because it's the one with no
counter-benchmark.

## 2. The structural speed wins survive the interpreter

The cache win is muted; the *structural* wins are not, and the Bible measured
them on this build (Part III):

- **`Packed*Array` over `Array[primitive]`** — contiguous, no per-element Variant
  box. (Measured by `S6`; note the docs even contradict themselves here,
  [#10300](https://github.com/godotengine/godot-docs/issues/10300) — so measure,
  don't trust prose.)
- **One batched manager loop over N per-node `_process` calls** — the per-node
  callback dispatch is the cost, and it's brutal: a 5,000-node repro ran **14×
  slower** self-processing than manually iterating the same work, 93% of CPU lost
  to per-node `StringName` dispatch
  ([#98175](https://github.com/godotengine/godot/issues/98175)). That's Part IV
  **D8**, and it's a structural decision — *where the loop lives* — not a
  micro-optimization.
- **Groups are HashMap-backed** — O(1) membership, so existence-based processing
  (argument 1) is also the fast shape, not a correctness tax (Part IV **D2a**).

These are interpreter-proof because they're about *how many Variant operations
happen*, not about cache lines. Fewer boxes, fewer dispatches, fewer allocations.

## 3. Godot itself is data-oriented under the hood — you're following it, not fighting it

The strongest Godot-specific argument: **the engine's own fast path is DOD.**
RenderingServer, PhysicsServer, NavigationServer operate on flat RID handles and
batched arrays; "the whole scene system is *optional*" and built on top of them
([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)).
Even the engine lead, defending the OOP scene tree, concedes the optimization
lives in the data-oriented layer: "Godot uses plenty of data-oriented
optimizations for physics, rendering, audio… separate systems, completely
isolated"
([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).

When you write a manager that owns a `PackedVector3Array` of positions and a
`Dictionary[int, Record]` of state, you are not importing an alien paradigm —
you're doing one layer up exactly what the engine does one layer down. The scene
tree is the designer-friendly veneer; DOD is the substrate. Adopting it is
*alignment*, not rebellion.

## 4. You end up here anyway — so start here

Part VII's escalation ladder is, read honestly, a DOD on-ramp. Every rung the
engine hands you when the scene tree buckles is more data-oriented than the last:

```
scene tree  →  batched manager  →  MultiMesh  →  servers direct
(per-node)     (Array[T] loop)     (one draw)    (RID + flat arrays)
   OOP    ───────────────────────────────────────────►  pure DOD
```

`MultiMesh` holds 1M instances at 144 FPS; servers-direct holds 1M at ~160 FPS
where the per-node version died in the thousands
([ezcha](https://ezcha.net/news/5-16-26-rendering-a-million-objects-in-godot)).
The destination of every Godot performance story is the data-oriented end of
that line. If that's where scale forces you, the cheap move is to *think* in
data from the start — POD `Def`s, manager-owned collections, IDs across system
boundaries — so the climb is a refactor of degree, not a rewrite of paradigm.
Retrofitting DOD onto a graph of fat `Enemy` objects that each own their state is
the expensive version.

## The "premature optimization" objection, answered

The reflexive rebuttal is Knuth. It doesn't apply, for two reasons.

First, **DOD is architecture, not optimization.** Knuth's "critical 3%" is about
hand-tuning a hot loop. DOD is about *which loops are possible* — data shape
gates the design space before a single line is tuned. Godot's own docs make
exactly this distinction: "performant software results from performant design
decisions made at the architectural stage, before coding begins"
([general_optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)).
Acton is blunter — he calls the premature-optimization quote "the most abused of
all time," because it's used to wave away *thinking about data* as if that were
micro-tuning.

Second, **the adoption cost is near zero and the retrofit cost is high.** Making
`alive` a group instead of a bool, passing an ID instead of a pointer, putting a
transform on a `System` instead of a method — none of these is slower to *write*.
They're the same line count. The asymmetry is all on the back end: the bool
desync bug, the stale-pointer crash, and the untestable method are expensive to
*undo*. You're not paying up front for a speculative gain; you're declining to
take on debt.

## The one concession that keeps this honest

DOD has a real failure mode, and the Bible flags it as hard as it advocates the
rest: **don't normalize speculatively.** Don't build an ID-indirection layer for
a reference that never leaves its own subtree. Don't split one class into five
containers before a second system needs the data. Don't ECS-ify code that runs
once. Three similar lines beats a premature abstraction, and you measure dispatch
before you optimize it (Part IV's closing rules). DOD is a default for *shape*,
not a license to over-engineer — and a parent-owned child node is still a direct
typed reference, not an integer ID.

That concession is what makes the rest credible. The argument isn't "always ECS,
always SoA, always indirection." It's narrower and harder to refute:

## The ask, in one line

**Model the transform on N things, not the thing; encode state as membership,
reference by ID across boundaries, keep behavior in pure transforms — and you get
correctness for free, speed where the interpreter still allows it, and alignment
with the engine's own substrate, at no extra cost to write and large savings not
to retrofit.** The cache win is a bonus you mostly collect in C++. The rest you
collect in GDScript today, at nine entities or nine thousand.
