# Part V — Architecture

Where things live. A cross-project skeleton + a decision rubric for "where does
X go?" and "what shape should this be?"

Draws from [`../rules/architecture.md`](../rules/architecture.md).

## Outline
- directory layout: data vs behavior vs scenes, leaves of the dependency graph
- canonical autoloads vs static-only `class_name` globals
- **autoload scripts must not declare `class_name`** (name collision)
- naming by kind (Def / Record / System / Registry / Manager)
- subsystem shape templates: Registry, Manager, HUD facade, pickup base
- the decision rubric table

*Status: outline.*
