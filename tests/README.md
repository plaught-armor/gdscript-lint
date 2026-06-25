# gd-lint test suite

Asserts `hooks/gd-lint.py` catches every rule it claims to, on GDScript the
Godot engine actually accepts.

## Run

```bash
bash tests/gd-lint/run.sh                 # parse-validate + assert
SKIP_GODOT=1 bash tests/gd-lint/run.sh    # skip the Godot parse pass (faster)
GODOT_BIN=/path/to/godot bash tests/gd-lint/run.sh
```

Exit 0 = all fixtures pass. Exit 1 = a missed detection, a false positive, or a
fixture Godot can't parse.

## What it covers

The **deterministic** rules `gd-lint.py` enforces — the full set the linter is
responsible for:

Each finding carries a category — **CORRECT** (bug), **PERF** (speed), **STYLE**
(idiom) — in the output: `path:line: RULE [CATEGORY]: msg`.

| Rule | Cat | Fixture | Checks |
|---|---|---|---|
| C1   | CORRECT | `c1.gd` | (see below) |
| C3   | CORRECT | `c3.gd`       | `var x: Array[T] = coll.filter()/.map()` flagged; `.assign(coll.filter())` not |
| C14  | CORRECT | `c14.gd`     | `var x: Array[T] = range()` flagged; `.assign(range())` not |
| C9   | CORRECT | `c9.gd`, `c9_refcounted.gd` | reserved Node method redefined flagged; domain `get_name()` on RefCounted not (base-scoped). `# no-godot-validate` — engine itself rejects these |
| P22  | PERF (advisory) | `p22.gd` | global `clamp/abs(0.5…)` flagged; `clamp(int)`, `clampf`, `vec.lerp()` method not |
| H1   | PERF | `h1.gd`       | `:=` flagged; `:=` inside string / comment not |
| H2   | `h2.gd`       | untyped `for x in` flagged; `for x: T in` not |
| S1   | `s1.gd`       | inline `func(...)` lambda flagged; named func not |
| C1   | `c1.gd`       | `const Packed*Array` flagged; `var` packed / `const int` not |
| S6   | `s6.gd`       | `Array[int/Vector2/String]` flagged; `Array[Vector2i/StringName/bool]` (no packed variant) not |
| S6b  | `s6.gd`       | typed `: Packed*Array = Packed*Array()` / `([...])` flagged; bare literal, var-conversion, arg-position not |
| D7b  | `d7b.gd`      | value-only `match` flagged; binding/destructure `match` not |
| L1   | `loops.gd`    | `range(coll.size())` flagged; 2-arg `range(0, n)` not — **advisory** |
| L2   | `loops.gd`    | manual descending `while` counter flagged; value-drain / condition `while` / descending `range` not — **advisory** |
| L3   | `loops.gd`    | `range(N)` / `range(0, N)` flagged; `range(a≠0, b)` / 3-arg not — **advisory** |
| S15  | `s15.gd`      | `== ""` / `.size() == 0` flagged; `== "x"` / `.is_empty()` not |
| P12a | `p12a.gd`     | bare string to StringName method flagged; `&"x"` / excluded `get` not |
| —    | `suppress.gd` | `# gdlint: ignore[H1]` and bare `# gdlint: ignore` suppress |
| —    | `disabled.gd` | `# gdlint: disable-file` skips the whole file |

## What it does NOT cover

Only `gd-lint.py`'s 7 syntactic rules are deterministic and unit-testable here.
The rest of `rules/gdscript/` — engine-bug lifecycle (C2/C3/C5/C7/C8/C11/C17),
DOD shape (D1–D11), and most typing/style/perf rules — need whole-program or
design judgment and are enforced by the `gdscript-reviewer` subagent (LLM), not
this suite. "All rules caught" here means all *linter* rules, not the full
corpus.

## Benchmarks & repros (the Bible's evidence)

Separate from the fixture suite: these back the measured claims and version-status
table in [`../bible/`](../bible/). They aren't pass/fail — they print numbers /
verdicts. Run with `godot --headless --script <file>` (the autoload one needs
`--path`, see its header). Results recorded in [`BENCH.md`](BENCH.md).

| Script | Backs | What it measures |
|---|---|---|
| `bench_loop_idiom.gd` | III §3 | L1/L2/L3 loop idioms |
| `bench_candidate_rules.gd` | III §4/§5 | P22 typed math, H13 call, C3/C14 iter, S11 print |
| `bench_dispatch_mechanism.gd` | III §1/§2 | `match`/`if-elif`/Callable dispatch; call-overhead ladder |
| `bench_static_typing.gd` | III §5, II §1 | typed vs untyped; `:=` vs explicit |
| `bench_group_ops.gd` | IV D2a | group membership O(1); `get_nodes_in_group` alloc; `is` vs `is_in_group` |
| `bench_convention_dispatch.gd` | IV D7a | `keys()[id].to_lower()` vs `if/elif` helper |
| `bench_dict_access.gd` | I P9 | `d.key` vs `d["key"]` (the #68834 perf gap, fixed 4.4) |
| `autoload_bench_proj/` | III §2 | autoload global-ident call (needs a real project) |
| `repro_typed_collections.gd` | I (C1/C2/C3/C14/C16) | re-tests const/typed-collection bug status on this build |
| `repro_lifecycle.gd` | I (C7/C8/C10/H8/M9/C11/C2a + C3.map) | re-tests object-lifecycle bug status |
| `repro_cycle_proj/` | I (C17) | real `.tres ↔ .tscn` ext_resource cycle — needs a project |
| `repro_async_proj/` | I (C5/C6) | await-across-free + coroutine-after-`queue_free` — needs a frame loop |
| `repro_c4_covariance.gd` | I (C4) | typed-array variance — element-covariance, `assign()`, invariant direct assign |
| `repro_node_leak.gd` | I (C13) | unparented `Node.new()` leak vs `free()` control (OBJECT_COUNT) |
| `repro_h12_proj/` | I (H12) | `@export` Resource survives scene load — needs a project |
| `repro_assert_proj/` | I (C12) | `assert()` body runs in debug, stripped in release — run under both an editor (debug) and a `linux_release` template (release) build |

The two `repro_*` scripts are how the Part I version-status table's "Re-tested
4.8.dev" column was filled — re-run them on your own target before trusting any
"fixed" verdict.

## How a fixture works

Each `fixtures/*.gd` is self-contained, parse-valid GDScript. A line that should
trigger rule `R` carries a trailing `# EXPECT R`. Lines with no marker are
negatives — gd-lint flagging one is a false-positive failure. The runner builds
the expected set from the markers and asserts it equals gd-lint's output exactly.

## Add a rule

1. Drop `fixtures/<rule>.gd`: at least one violating line marked `# EXPECT <RULE>`
   plus clean negative lines exercising the rule's boundary (the case that must
   NOT flag).
2. Keep it parse-valid — `godot --check-only` runs over every fixture.
3. `bash tests/gd-lint/run.sh` — the runner auto-discovers the new fixture.
