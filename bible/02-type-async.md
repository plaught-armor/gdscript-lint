# Part II — Type system & async

Static typing rules, lambda capture semantics, and the `await`/coroutine traps
that produce non-deterministic, hard-to-reproduce bugs.

Draws from [`../rules/type-async.md`](../rules/type-async.md).

## Outline
- always `var x: T = v`, never `:=`; typed `for x: T in` (perf — see Part III)
- no inline lambdas (formatter breaks them); lambda capture: by-value locals,
  by-ref members (#69014)
- no `await` in `_ready()`; signal `await` needs a timeout + `is_instance_valid`
  after the resume
- concurrent coroutine resume races — flag + poll
- Node method-name collisions (`get_name`, etc.) — the engine warns; so does the
  linter (C9)
- typed math fns in hot paths (`clampf`/`absf`/…)

*Status: outline.*
