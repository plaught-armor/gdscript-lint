# Part VII — Architecture types: when & why

Part V handed you *one* skeleton — a default shape that drops onto a new project
without re-litigating. This part steps back and asks the prior question: **which
structural paradigm is that skeleton an instance of, and when should you reach
for a different one?**

**In plain terms:** there are several big-picture ways to organize a game's code,
and they suit different sizes of game. This part walks through each one, says
when it earns its keep, and points out where the official guidance and the
community guidance disagree.

Four paradigms compete for the "how is this game structured at the bones" slot:

1. **Scene-tree composition** — the Godot-native default. Nodes carry data *and*
   logic; you compose by nesting and instancing scenes.
2. **Composition vs inheritance** — not one paradigm but an axis that runs
   through the other three; Godot gives you three *different* inheritance
   mechanisms and one composition mechanism, and they're easy to confuse.
3. **Data-oriented design (DOD)** — separate data (POD) from behavior
   (transforms over collections); shape data by access pattern. This is the
   bias the rest of the Bible already carries (Part IV).
4. **Entity-Component-System (ECS)** — one *specific* implementation of DOD:
   entities are IDs, components are columnar storage, systems iterate.

The honest through-line, supported by both the engine maintainers and the
measured numbers in 7e: **in Godot 4.x you use the scene tree until a profiler
says otherwise, and when it does, the next step is almost always
`MultiMesh` + the servers — not an ECS framework.** ECS earns its keep at a
scale most projects never reach. The sections below give the *when* for each,
with the sources, and they flag — rather than paper over — the places where the
official docs, the engine lead, and the community teaching resources genuinely
disagree.

**In plain terms:** stick with Godot's built-in way of doing things until
something measurably slows down. When it does, the right next step is usually a
lower-level Godot tool (drawing many copies of one thing at once, or talking
directly to the rendering/physics engine), not switching to a whole different
architecture style.

A note on sourcing: this part is less "measured on a build" than Parts I–IV
(architecture is shape, not a benchmark), and more "what do the primary sources
actually say." Where a number exists it's cited and version-flagged; where the
sources conflict, both are cited and the conflict is named.

---

## 7a. The Godot-native paradigm: scene-tree composition

**In plain terms:** Godot's built-in way is to build small reusable "scenes"
(like prefabs) and nest them inside each other to make bigger ones. Save one
`Coin` scene, drop 300 copies into a level, and changing the original updates
them all.

A Godot game is a tree of scenes, and each scene is a tree of nodes
([nodes_and_scenes](https://docs.godotengine.org/en/stable/getting_started/step_by_step/nodes_and_scenes.html)).
Nodes are "the fundamental building blocks"; a saved scene "works as a blueprint:
you can reproduce it in other scenes as many times as you'd like"
([instancing](https://docs.godotengine.org/en/stable/getting_started/step_by_step/instancing.html)).
That instancing relationship is the whole paradigm: you build a `Coin.tscn`
once, instance it 300 times, and editing the blueprint propagates project-wide.

The framing matters, and two pieces of common vocabulary are subtly *not* what
the official docs say:

- **"Component" is community vocabulary, not official.** GDQuest calls nodes
  "components in a scene"
  ([gdquest](https://www.gdquest.com/tutorial/godot/design-patterns/intro-to-design-patterns/)),
  and it's a useful mental model, but the docs deliberately say **blueprint /
  template / new node type** instead — "scenes work like new node types in the
  editor… the instance appears as a single node with its internals hidden"
  ([nodes_and_scenes](https://docs.godotengine.org/en/stable/getting_started/step_by_step/nodes_and_scenes.html)).
  If you say "component" on a Godot team, half the room hears "ECS component" and
  the other half hears "child node." Disambiguate.
- **It's aggregation, not strict composition.** "Godot's node trees form an
  aggregation relationship, not one of composition"
  ([scene_organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)).
  The everyday-engineering sense ("a scene *composes* nodes") and the OOP-strict
  sense (composition = child's lifetime is bound to the parent's) collide on this
  word. The docs use both senses on different pages. The practical rule the same
  page gives: a parent-child edge is real composition only when "removing the
  parent reasonably mean[s] the children should also be removed"; sub-scenes
  "should have no dependencies."

### Communication: "call down, signal up"

The phrase is community vernacular (kidscancode, gogogodot); the *principle* is
in the official docs, unnamed: connect to a signal to "respond to behavior, not
start it"
([scene_organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)).
The canonical shape: a node reaches **down** to children via `get_node()` /
`$Child`; it talks **up** or **sideways** via signals; the *common parent* wires
the connections
([kidscancode node communication](https://kidscancode.org/godot_recipes/4.x/basics/node_communication/index.html)).
This is exactly Part V's M11 (push-injection from the scene-root) seen from the
communication side, and it's why signals exist as a first-class language feature
— see Part III for their cost (≈3× a direct call) and Part IV **P18** for when
that cost is a bug.

```gdscript
# Good — parent reaches DOWN to a child by direct method call; the child talks UP
# via a signal the common parent connects (M11 push-injection, seen from comms).
class_name Enemy extends CharacterBody3D
signal died(id: int)                      # up: announces, doesn't act on the result
func take_hit(amount: int) -> void:       # down: the parent calls this on the child
    _health -= amount
    if _health <= 0:
        died.emit(get_instance_id())

class_name Arena extends Node             # the common parent owns the wiring
func _ready() -> void:
    for e: Enemy in _spawn_wave():
        e.died.connect(_on_enemy_died)    # up-signal handled here, not in the enemy
```

### Node vs Resource — the orthogonal axis

**In plain terms:** Godot gives you two kinds of object. A "Node" is something
active that lives in the scene and can run code every frame. A "Resource" is
just a chunk of saved data sitting on disk (like a config file). Use Resources
for things that *are* data; use Nodes for things that *do* stuff.

Not everything should be a Node. "Resources are data containers. They don't do
anything on their own"
([resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html));
they're "nearly as lightweight as Object/RefCounted" while a Node "carries
signals + tree state + process slots + lifecycle + owner + groups + path" even
for plain data
([node_alternatives](https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html)).
This is Part IV **D1** (POD as `Resource`/`RefCounted`) and the architecture
decision-rubric row "Data class: Resource or RefCounted?" The Bible's whole
`Def`/`Record` split lives here: a thing that *is data* is a Resource, a thing
that *acts* is a Node.

### When scene-tree composition is the right default

It is the right default for the regime most games live in. The engine lead's
own framing: "most games are generally just in the hundreds of objects at most,"
and the Node tree is the correct tool below the point where servers/DOD earn
their keep (≈"dozens of thousands of objects")
([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
The official optimization guidance agrees from the other direction: bypassing
nodes is "reserved for when other avenues of optimization have been exhausted"
([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)).

7e has the measured break-down points. The short version: the scene tree stops
being free somewhere in the low thousands of *actively-processing* nodes, and
much sooner for physics bodies.

---

## 7b. Composition vs inheritance — three axes, kept distinct

**In plain terms:** "composition over inheritance" is a popular slogan, but in
Godot it can mean three totally different things depending on whether you're
nesting scenes, extending a script, or extending a scene. People talk past each
other because they're each thinking of a different one of the three.

"Composition over inheritance" is a slogan that means three different mechanical
things in Godot, and conflating them is the single most common architecture
confusion. There is **no official "Inheritance vs Composition" doc page** — the
phrase appears only in third-party material (Packt's *Game Development Patterns
with Godot 4*, community tutorials). So the axes below are reconstructed from the
mechanics docs, not handed down.

| Axis | Mechanism | Reuses | Default? |
|---|---|---|---|
| **A. Node composition** | nest/instance scenes | structure + wiring | yes — the unit of reuse |
| **B. Script inheritance** | `extends` | behavior (imperative) | for genuine is-a |
| **C. Scene inheritance** | `.tscn` inherits `.tscn` | setup/shape, *not* behavior | exception only |

And one orthogonal choice — **Resource subtype inheritance** — which is the one
place the docs are unambiguously pro-inheritance.

### The genuine maintainer-vs-community split

**In plain terms:** the engine's lead developer says Godot leans on inheritance
on purpose; popular community teachers say the opposite. Both are looking at
the same node tree and drawing different conclusions — so the disagreement is
real, not just framing.

Surface this rather than pretend there's consensus:

- **Linietsky defends inheritance.** "Godot… makes heavy use of inheritance, and
  does composition at a higher level… as inheritance is preferred (for what would
  be implicit relationships between components in ECS), these relationships are
  now explicit in the inheritance chain"
  ([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
- **GDQuest pushes composition.** "Godot's nodes already allow you to favor
  composition over inheritance"
  ([gdquest](https://www.gdquest.com/tutorial/godot/design-patterns/intro-to-design-patterns/)).

Both are describing the *same* node tree. The split is real, not emphasis. The
reconciliation the Bible takes: **compose with nodes (Axis A) by default; use
script inheritance (Axis B) for a genuine is-a that shares a behavior body;
avoid scene inheritance (Axis C) except for the narrow setup-sharing case.**

### Axis A — Node composition (the default unit of reuse)

"If one wishes to create a concept particular to their game, it should always be
a scene"; a script alone is for cross-project tools
([scenes_versus_scripts](https://docs.godotengine.org/en/stable/tutorials/best_practices/scenes_versus_scripts.html)).
Wiring options "hide the points of access from the child node… keeps the child
loosely coupled to its environment"
([scene_organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)).
Godot has no `interface` keyword; "Godot interfaces" are duck-typing + groups +
node names
([godot_interfaces](https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_interfaces.html))
— which is exactly why Part style-rule **H13** bans `has_method`/`call` duck
dispatch in favor of a shared base class: the language *lets* you duck-type, and
that's the trap.

The classic composition win the sources cite: a behavior that several unrelated
kinds need but can't inherit from a common base (GDQuest's example: a
power-distribution behavior shared across machine types that "can't inherit from
both"). That's a child-node-as-behavior, dropped into each scene.

```gdscript
# Good — a behavior several unrelated kinds need but can't share by inheritance,
# dropped in as a child node. Machine and Door both hold a PowerSink; neither
# inherits from the other, and the behavior is reused by composition.
class_name PowerSink extends Node         # the reusable behavior, as a node
signal power_lost
var _draw: int = 0
func set_supply(watts: int) -> void:
    if watts < _draw:
        power_lost.emit()

class_name Machine extends Node3D
@onready var _power: PowerSink = $PowerSink   # composed in, not inherited
```

### Axis B — Script inheritance (`extends`)

The official docs describe `extends` mechanics but give **no when-to-use rubric**
([what_are_godot_classes](https://docs.godotengine.org/en/stable/tutorials/best_practices/what_are_godot_classes.html)).
The stable community pattern (3.x → 4.x): a shared `Character.gd` →
`Player.gd` / `NPC.gd` when they genuinely share a behavior body. The known
structural failure: "a tank that's both enemy and turret" doesn't sit cleanly in
single inheritance
([forum: inheritance vs composition](https://forum.godotengine.org/t/godot-design-flaw-inheritance-vs-composition/35115))
— that's the signal to move the shared slice to Axis A (a child node).

```gdscript
# Good — shared behavior body in a base script; Player/NPC are a genuine is-a.
class_name Character extends CharacterBody3D
var health: int = 100
func take_damage(amt: int) -> void:
    health -= amt

class_name Player extends Character
func _physics_process(_dt: float) -> void:
    _read_input()                    # adds behavior; inherits take_damage

# Bad — "a tank that's both enemy and turret" won't sit in single inheritance.
# The shared slice belongs in a child node (Axis A), not a second base class.
class_name Tank extends Enemy        # ...and also needs Turret's aiming? stuck.
```

### Axis C — Scene inheritance (`.tscn` inherits `.tscn`)

**In plain terms:** you can also have one whole *scene* inherit from another
scene — keep the parent's layout, override a few children. It shares how things
are set up, not what they do, and the editor still has long-standing bugs
around it. Use it only for the narrow "shared skeleton" case.

This is 5dd. The docs are explicit about its *limit*: "Scenes can define
how an extended class initializes, but not what its behavior actually is"
([scenes_versus_scripts](https://docs.godotengine.org/en/stable/tutorials/best_practices/scenes_versus_scripts.html))
— it shares **setup/shape, not behavior**. And it carries real, still-live 4.x
footguns that argue for keeping it to the narrow `_pickup_base.tscn` case:

- Can't delete or reparent base-scene nodes in a derived scene
  ([#3084](https://github.com/godotengine/godot-proposals/issues/3084)).
- Renaming a base node breaks every derived scene — no stable scene-local ID
  ([#6291](https://github.com/godotengine/godot-proposals/issues/6291)). (This
  is the exact constraint 5dd warns about: "don't rename base children
  without sweeping derived scenes.")
- Root-of-parent-scene edits don't always propagate to inherited instances
  ([#113981](https://github.com/godotengine/godot/issues/113981)).
- Deep inheritance chains can freeze the editor 60s+ on hierarchy edits
  ([#92612](https://github.com/godotengine/godot/issues/92612)).

`instancing.html` never even mentions scene inheritance — the implicit doc
stance is "instancing is the default, scene inheritance is the exception."

### The orthogonal one — Resource subtype inheritance

The one place the docs lean *into* inheritance: Resource sub-types that extend
behavior on shared data, "Inspector-compatible… nearly as lightweight as
Object/RefCounted"
([node_alternatives](https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html)).
`WeaponDef extends ItemDef` is fine and idiomatic. Data inheritance doesn't drag
in the SceneTree, so the Axis-C footguns don't apply.

---

## 7c. Data-oriented design in Godot

**In plain terms:** data-oriented design says: programs are mostly about turning
data into other data, so design the data first and write small functions that
transform it. The classic speed win comes from packing data so the CPU can read
it fast — but GDScript wraps everything in a generic box, so most of that
hardware win doesn't reach your scripts. The *shape* benefits still do.

DOD's thesis (Mike Acton, CppCon 2014): "the purpose of all programs… is to
transform data from one form to another"; the *three lies* are that software is
a platform, that code should model the world, and that code matters more than
data
([Acton talk](https://www.youtube.com/watch?v=rX0ItVEVjHc),
[isocpp summary](https://isocpp.org/blog/2015/01/cppcon-2014-data-oriented-design-and-c-mike-acton)).
This is Part IV's opening verbatim — DOD is the Bible's house paradigm.

### The honest GDScript caveat

Acton's argument is grounded in **cache lines**, and that's where translation to
GDScript leaks. GDScript is interpreted and Variant-boxed; the engine's own
proposal admits it: "Classes are not lightweight in Godot… memory is all over
the place so there is not much cache locality"
([#7329](https://github.com/godotengine/godot-proposals/issues/7329); struct
types would need Variant-level changes,
[#2816](https://github.com/godotengine/godot-proposals/issues/2816)). Linietsky's
framing is the same: "Godot uses plenty of data-oriented optimizations for
physics, rendering, audio… they are, however, separate systems and completely
isolated"
([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
**DOD's raw cache win lives in the C++ servers, not in your GDScript.** So what
survives translation to a managed language?

What survives is the *structural* half of DOD, which still pays in GDScript even
without C++ cache locality:

- **`Packed*Array` over `Array[primitive]`** — contiguous, no per-element
  Variant box. Class docs: "packs data tightly… generally faster to iterate on
  and modify"
  ([PackedFloat32Array](https://docs.godotengine.org/en/stable/classes/class_packedfloat32array.html)).
  ⚠️ **Sources contradict**: a GDScript-reference page says packed arrays "tend
  to run slower than generic arrays," flagged unresolved in
  [godot-docs#10300](https://github.com/godotengine/godot-docs/issues/10300).
  Part III's `S6` benchmark on *this* build is the tiebreaker — measure, don't
  trust the prose. This is Part I **C1** territory (`const Packed*` is broken)
  too.
- **Existence-based processing via groups** — group membership over `bool`
  flags. Confirmed Part IV **D2a**: groups are HashMap/HashSet-backed, O(1) for
  add/remove/`is_in_group`, and the only footgun is `get_nodes_in_group()`
  allocating a fresh Array per call
  ([#7080](https://github.com/godotengine/godot-proposals/issues/7080)).
- **Batched manager loop over per-Node `_process`** — Part IV **D8**. The
  measured payoff is in 7e.
- **Per-member state in `Dictionary[int, Record]` keyed by `get_instance_id()`**
  — the SoA-without-structs workaround, since GDScript has no struct type
  ([#7329](https://github.com/godotengine/godot-proposals/issues/7329),
  [#290](https://github.com/godotengine/godot-proposals/issues/290)).

### DOD is not ECS

**In plain terms:** data-oriented design is a way of *thinking*; ECS is one
specific framework that implements it. You can absolutely follow data-oriented
design with plain arrays and a manager script — no ECS library required. The
two often get treated as the same thing; they aren't.

A misconception worth killing: "structuring something in a data-oriented way
could very well mean using AoS or any other data structure that fits the problem
— [it] is not as much about a specific design pattern or optimizing for CPU
caches… [but] an approach to solving problems" (Sander Mertens, *flecs* author —
[why vanilla ECS is not enough](https://ajmmertens.medium.com/why-vanilla-ecs-is-not-enough-d7ed4e3bebe5),
[yoyo-code: DOD is not ECS](https://yoyo-code.com/data-oriented-design-is-not-ecs/)).
You can — and in GDScript usually should — do DOD with a manager owning a typed
`Array` and a couple of `Packed*Array`s, with **no ECS framework at all**. ECS
(7d) is one implementation of DOD, not its definition.

### When DOD is worth it, when it's premature

The official docs quote Knuth ("premature optimization is the root of all evil")
and immediately temper it: "performant software results from performant design
decisions made at the architectural stage, before coding begins… always use
profiling to guide your efforts"
([general_optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)).
The thresholds in the sources differ **by layer**, which is not a contradiction:

- Game-logic DOD refactor is "a must" for "dozens of thousands of objects" —
  "rare exceptions" like city builders, sandboxes, large-unit strategy
  ([why-isnt-godot-ecs](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
- Rendering/physics server-direct kicks in much sooner, "hundreds of similar
  objects"
  ([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)).

Part IV's inline-perf checklist is the operational version: `(call cost ns) ×
(calls/sec)` vs the 16.6 ms frame budget. Below ~10,000 ns of impact, the DOD
refactor is moving a needle that isn't the bottleneck.

---

## 7d. Entity-Component-System (ECS)

**In plain terms:** ECS is a particular architecture where every game thing is
just an ID number, its data lives in big parallel tables (one column per kind
of data), and the game logic is a set of routines that scan those tables. Done
right, it's extremely fast at scale. It's also a whole-project commitment, not
something you sprinkle into one feature.

ECS makes entities into IDs, components into columnar (struct-of-arrays)
storage, and behavior into systems that query and iterate. Mertens'
one-liner: "inheritance is a 1st-class citizen in OOP; composition is a
1st-class citizen in ECS"
([ecs-faq](https://github.com/SanderMertens/ecs-faq)). Archetype storage keeps
entities with the same component set contiguous, so a system walks one cache-warm
column at a time
([building an ECS: storage in pictures](https://ajmmertens.medium.com/building-an-ecs-storage-in-pictures-642b8bfd6e04)).

### Why Godot core is not ECS

This is the maintainer position, canonical and reaffirmed: "Godot does
composition at a higher level than in a traditional ECS" — nodes carry data and
logic, data-oriented optimization is isolated to the servers, and "for typical
games with hundreds of objects… the architectural choice is negligible"
([why-isnt-godot-ecs, Feb 2021](https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/)).
Reaffirmed Feb 2026: the engine team "will not adopt ECS" and points
ECS-wanters at other engines
([forum: ECS-powered SceneTree](https://forum.godotengine.org/t/possibly-an-ecs-powered-scenetree-for-godot/133892)).
Even the softer "components, not full ECS" proposal landed nowhere
([#2796](https://github.com/godotengine/godot-proposals/issues/2796)). The
article is *not* anti-ECS dogma — it explicitly suggests Godex if you need it —
but the engine will not be one.

### The addons (Godot 4.x)

| Addon | Language | Maturity | Use it for |
|---|---|---|---|
| [GECS](https://github.com/csprance/gecs) | pure GDScript | active (v8, 2026), asset-lib installable | ECS *patterns* — queries, relationships, decoupling. **Not** documented to beat the scene tree on raw speed. |
| [Godex](https://github.com/GodotECS/godex) | C++ engine **module** | pre-1.0, tracks master | the performance-credible path — but it's a fork, not a GDExtension; you own the build pipeline. |
| [godot-bevy](https://github.com/bytemeadow/godot-bevy) | Rust | active | bringing Bevy's archetype ECS into a Godot host; niche, Rust dependency. |

The honest framing: **if you want ECS *patterns* in pure GDScript, GECS; if you
want ECS *performance*, you're looking at Godex (fork risk) or godot-bevy (Rust).**
No credible published benchmark shows GECS-on-GDScript beating the raw scene tree
at scale — its value is decoupling, not throughput.

### When ECS pays — and when it's the wrong call

**In plain terms:** ECS shines for huge crowd-style games — thousands of
soldiers, zombies, units — and is overkill for puzzle games, platformers, or
UI-heavy apps. Even shipped games using ECS report that it can backfire when
your entities are too varied or change shape often, so the picture isn't all
upside.

Unity's DOTS rationale is the clearest external "when" (the cases generalize):
large static environments, competitive multiplayer with prediction, and
"high-performance massive scale" — RTS crowds, zombie hordes, heavy sim; and the
explicit anti-cases, "simple 2D platformers, puzzle games, or UI-heavy apps"
([unity DOTS](https://unity.com/dots)). Critically, Unity warns ECS "generally
is meant to form the foundation of your whole project" — not a selective drop-in.

The counter-discourse is essential and ships-evidence-backed. Moonside Games
(*Samurai Gunn 2*), ["Archetypal ECS Considered Harmful?"](https://moonside.games/posts/archetypal-ecs-considered-harmful/):
archetypal ECS fails under (a) dynamic component churn — add/remove migrates an
entity across archetypes, copying every unrelated component; (b) diverse entity
types fragmenting into many archetypes, killing the locality the benchmarks
assume; (c) external spatial dependencies (collision broadphase) needing their
own structure. Their shipping numbers: ~300–500 FPS on sparse storage vs ~5 FPS
archetypal. Mertens (sells archetypes) vs Moonside (archetypes failed us in a
shipped game) is the central honest tension — **cite both; neither is wrong, they
hit different workloads.**

---

## 7e. The escalation ladder (and the measured thresholds)

**In plain terms:** don't pick your architecture up front. Start with the
default scene tree; if it gets slow, climb one rung at a time — batch processing
in a manager, then draw many copies at once, then talk to the engine's internal
servers directly. Each rung gives up a convenience and buys more headroom.
Most games never leave the bottom two rungs.

The decision is not "OOP or DOD or ECS" picked up front. It's a ladder you climb
*only when a profiler points at the rung you're on*. Each rung trades engine
convenience (Inspector, `print_tree`, per-instance culling, collision) for
throughput.

| Rung | What | Gives up | Reach for it when |
|---|---|---|---|
| 1. Scene tree | nodes self-process | nothing | default — hundreds of objects |
| 2. Batched manager | one `_process` loops a typed `Array[T]`; per-node `set_physics_process(false)` | per-node autonomy | per-node tick is the profile hotspot (D8) |
| 3. `MultiMesh` | one draw call, N instances | collision, nav, per-instance frustum cull, per-instance logic (vertex shader only) | hundreds–thousands of *visual* duplicates |
| 4. Servers direct | `RenderingServer`/`PhysicsServer` on RIDs | Inspector, debug tree, sync reads | scene tree itself is the bottleneck |
| 5. ECS framework | columnar storage + systems | the whole engine's grain | dozens-of-thousands of churning entities **and** you need parallel system scheduling |

The measured break-down points (version-flagged; most are single-machine, not
lab-controlled — treat as order-of-magnitude):

**In plain terms:** here are the rough numbers where each tier stops keeping up.
Treat them as "this is roughly where things slow down," not exact limits —
they depend on what kind of node, what physics engine, and what the work
actually is.

- **Per-node processing falls off in the low thousands.** A C# repro: 5,000
  nodes self-`_Process` ran 200 FPS vs 2,800 FPS manually iterating the same work
  — 14×, with 93% of CPU in `StringName` compares for the per-node callback
  dispatch; closed "not planned" as architectural
  ([#98175](https://github.com/godotengine/godot/issues/98175)). General node
  perf "falls off around 50,000 objects"
  ([node_alternatives](https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html)).
  This is the empirical case *for* rung 2 (Part IV **D8**).
- **Physics bodies fall off much sooner, and the backend dominates.**
  `CharacterBody3D` on GodotPhysics: 10–30 units @60 FPS, 100+ under 10 FPS,
  250+ unplayable — `move_and_slide()` + AABB bound. **Jolt buys ~20×** (~800
  units); Jolt is default from 4.4
  ([slashskill](https://www.slashskill.com/godot-4-characterbody3d-vs-multimesh-scaling-hundreds-of-units-without-killing-performance/),
  [#93184](https://github.com/godotengine/godot/issues/93184)). Any single
  scale-ceiling number is wrong without naming the node type *and* the physics
  backend.
- **`MultiMesh` reaches the millions.** 1,000,000 instances at 144 FPS, then the
  `Transform3D` buffer bottlenecks
  ([proposal #8647](https://github.com/godotengine/godot-proposals/discussions/8647)).
  vs `CharacterBody3D`: 1,000 MultiMesh instances hold 60 FPS where the physics
  path is long dead — but MultiMesh has *no collision*.
- **Servers direct is the real top end.** A 12,800-object scene: per-object nodes
  (51,204 nodes total) ran ~110 FPS; the same scene as `MultiMesh` +
  `RenderingServer`/`PhysicsServer` direct collapsed to **4 nodes** and held
  ~160 FPS at **1,000,000** objects
  ([ezcha: rendering a million objects](https://ezcha.net/news/5-16-26-rendering-a-million-objects-in-godot)).
  Godot's own scene system is built on these servers — "the whole scene system
  is *optional*"
  ([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)).

Two hard warnings on rung 4 from the official docs: **never read back from a
server every frame** ("calling functions returning values… will stall them and
force them to process anything pending" — async pipeline)
([using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html));
and **RIDs are not GC-tracked — you must free them yourself** or leak (same).
That's Part I's resource-discipline rules (C5/C7/C13) one layer lower. An `RID`
is validator-tagged like an `ObjectID` (`rid_owner.h`: a 31-bit monotonic
validator over the 32-bit slot, so a stale handle fails the compare), but unlike
an `Object` nothing refcounts it for you — the leak, not a mistaken identity, is
what bites.

**The takeaway the sources converge on:** *profile your bottleneck, not your
entity count.* The thresholds above span two orders of magnitude depending on
node type, backend, and whether the cost is logic, physics, or draw. And note
that rung 5 (ECS) is reached almost never in indie Godot — the empirically
common escalation is 1 → 2 → 3 → 4. Godot's servers **are** the data-oriented
layer; you usually reach DOD by descending to them, not by adopting an ECS
framework on top.

---

## The shape, in one paragraph

Godot's native paradigm is scene-tree composition: nodes carry data and logic,
you reuse by instancing scenes, and you communicate call-down / signal-up.
"Composition over inheritance" resolves into three distinct mechanisms — node
composition (the default unit of reuse), script `extends` (for genuine is-a with
a shared behavior body), and scene inheritance (setup-sharing only, with live
4.x footguns) — plus Resource subtype inheritance, the one place inheritance is
unambiguously fine. Data-oriented design is the house bias, but its cache-line
argument lives in the C++ servers; what survives into GDScript is the structural
half — `Packed*Array`, batched managers, group-membership state. ECS is one
implementation of DOD, not its definition, and Godot core will never be one — you
adopt it only at dozens-of-thousands of churning entities with parallel
scheduling needs, a scale most projects never hit. When the scene tree does
become the bottleneck, the measured escalation is batched manager → MultiMesh →
servers-direct, climbed one rung at a time, only where a profiler points. Profile
the bottleneck, not the entity count.
