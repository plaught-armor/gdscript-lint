#!/usr/bin/env python3
"""gd-lint — thin deterministic linter for the bespoke GDScript rule corpus.

Covers the *syntactic* subset of ~/.claude/rules/gdscript/ that a real linter
can catch cheaply and deterministically — the rules otherwise left to the LLM
`gdscript-reviewer` (expensive, non-deterministic). It is NOT a parser: it scans
text after masking out string literals and comments, so it stays dependency-free
(stdlib only — no tree-sitter, no pip) and portable across machines.

Design bias: HIGH PRECISION over recall. A finding here blocks an edit (via
gd-check.sh), so a false positive is costly; a miss is fine — the reviewer is
the recall backstop. When a construct is ambiguous, stay silent.

Rules (cite the corpus):
  H1   no ':='            — always 'var x: Type = value' (type-async.md)
  H2   typed 'for'        — 'for item: Type in ...' (type-async.md)
  S1   no inline lambda   — extract to named method (type-async.md)
  C1   no 'const Packed*' — reports byte-count size, reads 0.0 (engine-bugs.md)
  D7b  value-only 'match' — use if/elif (~5x dispatch overhead) (dod.md)
  S6   Array[primitive]    — prefer Packed*Array (style.md)
  S6b  Packed*([...]) ctor  — bare literal, annotation converts (style.md / C1)
  S15  .is_empty()        — not '== ""' / '.size() == 0' (style.md)
  P12a StringName literal  — '&"x"' not '"x"' for StringName-param methods (style.md)
  L1   range(x.size())     — iterate directly unless you need the index (advisory)
  L2   descending while    — manual countdown → 'for i in range(hi,lo,-1)' (measured ~2x faster) (advisory)
  L3   range(N)/range(0,N)  — 'for i: int in N' (range builds untyped Array, C14) (advisory)
  C3   Array[T] = .filter() — typed Array from filter/map returns untyped (#72566)
  C14  Array[T] = range()   — typed Array from range() returns untyped (#110659)
  C9   func get_name()/...   — redefining a reserved Node/Object method (collision)
  P22  clamp()/abs()/lerp()  — float math → clampf/absf/lerpf (~1.3x) (advisory)
  C11  sort_custom(func..<=)  — comparator must be strict '<'/'>' (#58878)
  M1   await in _ready()      — pauses init; call_deferred / separate coroutine
  P6   .pop_front()/.pop_at(0) — O(n) front-shift on Array (#45455) (advisory)
  H14  (x as T) after 'is T'  — redundant cast, 'is' already narrowed (advisory)
  H4   signal foo(a, b)        — untyped signal params (#110573); type them
  H13  has_method+call pair    — duck-typed dispatch → base class + 'is' (advisory)
  S11  print() in _process     — per-frame sync I/O; gate/remove (advisory)

Each finding is labelled with a CATEGORY: CORRECT (bug / wrong result), PERF
(speed), or STYLE (idiom). Output line: 'path:line: RULE [CATEGORY]: msg'.

Suppress: append '# gdlint: ignore' (whole line) or '# gdlint: ignore[H1]'
(one rule) to a line; '# gdlint: disable-file' in the first 5 lines skips file.

Severity: most rules are BLOCKING (exit 1 → the gate blocks the edit). L1/L2/L3
and P22 are ADVISORY — printed with a ' [advisory]' tag, exit stays 0, the gate
surfaces them as a non-blocking note. See ADVISORY set + tests/gd-lint/BENCH.md
(measure before promoting any of them to blocking).

Usage: gd-lint.py FILE [FILE ...]
Exit:  1 if any BLOCKING finding (lines 'path:line: RULE [CATEGORY]: msg');
       advisory-only or clean → 0. Internal errors fail OPEN — never wedge edits.
"""

from __future__ import annotations

import re
import sys

MAX_LINES = 100_000          # NASA-2: bound every scan
MAX_MATCH_ARMS = 256         # bound the per-match arm walk

# ---- comment / string masking ------------------------------------------------


def mask_code(lines: list[str]) -> list[str]:
    """Return per-line copies with string-literal + comment chars blanked.

    Preserves nothing about quoted content; structural tokens (':=', 'for',
    'match', 'const', 'func(') survive so the rules can match them without
    tripping on look-alikes inside strings or comments. Tracks triple-quoted
    strings across line boundaries.
    """
    masked: list[str] = []
    triple: str | None = None      # active ''' or \"\"\" delimiter, or None
    for raw in lines:
        out: list[str] = []
        i, n = 0, len(raw)
        if triple is not None:
            idx = raw.find(triple)
            if idx == -1:
                masked.append(" " * n)
                continue
            out.append(" " * (idx + 3))
            i = idx + 3
            triple = None
        while i < n:
            three = raw[i:i + 3]
            ch = raw[i]
            if three in ('"""', "'''"):
                end = raw.find(three, i + 3)
                if end == -1:
                    out.append(" " * (n - i))
                    triple = three
                    i = n
                else:
                    out.append(" " * (end + 3 - i))
                    i = end + 3
            elif ch == "#":
                out.append(" " * (n - i))
                i = n
            elif ch in ('"', "'"):
                j = i + 1
                while j < n:
                    if raw[j] == "\\":
                        j += 2
                        continue
                    if raw[j] == ch:
                        break
                    j += 1
                stop = min(j, n - 1)
                out.append(" " * (stop - i + 1))
                i = j + 1
            else:
                out.append(ch)
                i += 1
        masked.append("".join(out))
    return masked


# ---- line rules (table-driven, DOD D7 style) ---------------------------------

_RE_WALRUS = re.compile(r":=")
_RE_FOR_UNTYPED = re.compile(r"\bfor\s+[A-Za-z_]\w*\s+in\b")
_RE_LAMBDA = re.compile(r"\bfunc\s*\(")
_RE_CONST_PACKED = re.compile(r"\bconst\b.*\bPacked\w+Array\b")
_RE_SIZE_ZERO = re.compile(r"\.size\(\)\s*[=!]=\s*0\b")
_RE_EMPTY_CMP = re.compile(r"""[=!]=\s*&?(?:""|'')""")

# P12a: methods whose first string arg is UNambiguously a StringName. Curated
# narrow to keep false positives near zero — deliberately excludes overloaded
# names (get/set/call/connect/play) that often take a non-StringName first arg.
_P12A_METHODS = (
    "add_to_group", "remove_from_group", "is_in_group",
    "has_method", "emit_signal", "has_signal",
    "is_action_pressed", "is_action_just_pressed",
    "is_action_just_released", "is_action_released", "get_action_strength",
    "add_theme_color_override", "add_theme_font_override",
    "add_theme_font_size_override", "add_theme_constant_override",
    "add_theme_stylebox_override", "add_theme_icon_override",
    # meta API: name arg is unambiguously StringName, no non-StringName overload.
    "get_meta", "set_meta", "has_meta", "remove_meta",
)
_RE_P12A = re.compile(r"\b(?:" + "|".join(_P12A_METHODS) + r")\s*\(")
# P12a (decl site): a var/param/@export typed StringName or NodePath initialised
# with a BARE string literal — the annotation proves intent, so the literal
# should carry the matching sigil (&"x" for StringName, ^"a/b" for NodePath).
# Detected on masked (':  StringName ='), confirmed by peeking raw's first
# value char: '&'/'^' = already correct, '"'/"'" = bare → flag. A non-literal
# RHS (identifier, call) lands on a non-quote char and is left alone.
_RE_SN_DECL = re.compile(r":\s*StringName\s*=")
_RE_NP_DECL = re.compile(r":\s*NodePath\s*=")

# S6: only the element types that HAVE a Packed* variant. Vector2i/Vector3i/
# Vector4/StringName/bool deliberately excluded (no packed equivalent) — the
# trailing \] keeps Array[Vector2i] / Array[StringName] from matching.
_RE_ARRAY_PRIM = re.compile(r"\bArray\[(?:int|float|String|Vector2|Vector3|Color)\]")
# S6b: redundant Packed*Array constructor on a TYPED assignment — empty
# Packed*Array() or literal Packed*Array([...]) where a bare literal would
# convert via the annotation. Scoped to ': Packed*Array = Packed*Array(' so the
# conversion is provable on the line: arg position (foo(PackedByteArray())) and
# untyped contexts are NOT flagged — there '[]' would become a plain Array, not
# Packed. The (?:\[|\)) keeps a Packed*Array(existing_var) conversion out.
_RE_PACKED_CTOR = re.compile(r":\s*Packed\w+Array\s*=\s*Packed\w+Array\(\s*(?:\[|\))")
# L1: single-arg range(<expr>.size()) — the index-to-subscript smell. A 2-arg
# range(0, x.size()) is left alone (an offset start is a real range need).
_RE_RANGE_SIZE = re.compile(r"\bfor\s+\w+(?:\s*:\s*\w+)?\s+in\s+range\(\s*[\w.]+\.size\(\)\s*\)")
# L2: manual descending COUNTER via while → use 'for i in range(hi, lo, -1)'.
# Measurement (BENCH.md) showed descending range is ~2x FASTER than a hand
# while, inverting the original "descending -> while" idiom. Block-scanned in
# find_descending_while(); needs a numeric guard + literal decrement to avoid
# flagging value-drain loops (while health > 0: health -= damage).
_RE_WHILE_DESC = re.compile(r"^(\s*)while\s+([A-Za-z_]\w*)\s*(?:>=|>)\s*-?\d+\s*:\s*$")
# L3: count loop `for .. in range(N)` / `range(0, N)` → `for i: int in N`
# (range() builds an untyped Array — engine-bugs.md C14 #110659). Needs a
# paren-balanced arg split because range(coll.size()) has nested parens.
_RE_FOR_RANGE = re.compile(r"\bfor\s+\w+(?:\s*:\s*\w+)?\s+in\s+range\(")
# C3: typed Array assigned directly from .filter()/.map() — both return an
# UNTYPED Array (#72566), so the typed annotation is a lie; must go through
# .assign(). The ': Array[T] =' anchor excludes the correct 'x.assign(...)' form.
_RE_C3_FILTER = re.compile(r":\s*Array\[\w+\]\s*=\s*[\w.]+\.(?:filter|map)\(")
# C14: typed Array assigned from range() — range() returns an untyped Array
# (#110659). Same fix: .assign(range(...)) or iterate.
_RE_C14_RANGE = re.compile(r":\s*Array\[\w+\]\s*=\s*range\(")
# P22 (advisory PERF, ~1.3x): untyped GLOBAL math fn on a float-literal arg →
# typed variant. The (?<![\w.]) excludes method calls — vec.lerp()/vec.abs()/
# vec.clamp() are Vector methods, NOT the global fns and NOT replaceable by the
# f-variant. The (?=[^)]*\d\.\d) requires a float literal so int args
# (clamp(i, 0, 9), which want clampi) aren't mis-flagged.
_RE_P22 = re.compile(r"(?<![\w.])(clamp|abs|max|min|floor|ceil|round|lerp)\((?=[^)]*\d\.\d)")
# P6 (advisory PERF): Array front-removal is O(n) — pop_front shifts every
# remaining element down one ([#45455]). pop_at(0) is the same shift. Both names
# are Array-only (no String/Packed* variant) so the method name alone is a near-
# unambiguous Array signal. The pop_at form requires a literal 0 (a variable
# index can't be proven to be the front). Advisory because the cost is
# size x frequency, not size alone: one pop_front of a few-dozen-element array
# off the hot path is free, so blocking would be noise. It bites two ways —
# (1) a large array (hundreds+) shifted on a per-frame path, (2) a drain loop
# (pop_front until empty), where each O(n) shift over N iterations is O(n^2)
# regardless of starting size. The linter can't see the surrounding loop or the
# array's runtime length, so it flags the call and lets the human judge both.
_RE_POP_FRONT = re.compile(r"\.pop_front\(\s*\)|\.pop_at\(\s*0\s*\)")
# C11 (CORRECT, #58878): an Array.sort_custom() comparator must impose a STRICT
# weak ordering — it returns true iff a sorts strictly BEFORE b. A '<=' / '>='
# comparator returns true on equal elements too, which breaks the contract and
# yields an unstable / wrong sort. Scoped to an INLINE lambda comparator
# (sort_custom(func ...)) carrying a non-strict operator on the same line — the
# one form a line linter can see. A named-function comparator's body is out of
# view (the reviewer's job). S1 also fires on the inline lambda (extract it);
# C11 is the orthogonal correctness concern on the operator itself.
_RE_SORT_CUSTOM_LAMBDA = re.compile(r"\bsort_custom\s*\(\s*func\b")
_RE_NONSTRICT_CMP = re.compile(r"[<>]=")


def _range_args(m: str, open_idx: int) -> list[str] | None:
    # open_idx = index of '(' ; return top-level comma-split arg strings, or
    # None if unbalanced. Bounded by line length (NASA-2).
    depth = 0
    args: list[str] = []
    cur: list[str] = []
    for i in range(open_idx, len(m)):
        c = m[i]
        if c == "(":
            depth += 1
            if depth == 1:
                continue
        elif c == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(cur))
                return args
        if depth == 1 and c == ",":
            args.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    return None


# Each rule fn takes (raw, masked): masked = strings/comments blanked (for
# structural matching), raw = original (for quote-sensitive checks like &"x").
def rule_h1(raw: str, m: str) -> str | None:
    if _RE_WALRUS.search(m):
        return "H1: avoid ':=' — use 'var x: Type = value' (static typing ~40% faster)"
    return None


def rule_h2(raw: str, m: str) -> str | None:
    if _RE_FOR_UNTYPED.search(m):
        return "H2: type the loop var — 'for item: Type in ...' (untyped iter defeats optimization)"
    return None


def _match_paren(s: str, open_idx: int) -> int | None:
    # index of the ')' matching the '(' at open_idx, or None if unbalanced on s.
    depth = 0
    for i in range(open_idx, len(s)):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return None


def rule_s1(raw: str, m: str) -> str | None:
    # Flag only MULTI-STATEMENT inline lambdas (body on the following lines) —
    # those are what the formatter reflows and what's worth extracting (style.md
    # S1 / bible §02). A single-expression lambda `func(x): return x.id` is
    # explicitly NOT the target: content after the head ':' on the same line
    # exempts it.
    for mo in _RE_LAMBDA.finditer(m):
        close = _match_paren(m, mo.end() - 1)
        if close is None:
            continue
        k = close + 1
        while k < len(m) and m[k] in " \t":
            k += 1
        if k >= len(m) or m[k] != ":":
            continue                       # not a `func(...):` lambda head
        if m[k + 1:].strip() == "":        # nothing after ':' → multi-statement
            return "S1: no inline lambda — extract to a named method (formatter reflows multi-statement bodies; a single-expr `func(x): expr` is fine)"
    return None


def rule_c1(raw: str, m: str) -> str | None:
    if _RE_CONST_PACKED.search(m):
        return "C1: never 'const' a Packed*Array — use 'var'/'static var' (const reports byte size, reads 0.0)"
    return None


def rule_s15(raw: str, m: str) -> str | None:
    if _RE_SIZE_ZERO.search(m):
        return "S15: use '.is_empty()' not '.size() == 0'"
    for mo in _RE_EMPTY_CMP.finditer(raw):
        if m[mo.start()] != " ":          # the '==' is code, not inside a string
            return "S15: use '.is_empty()' not '== \"\"' / '== &\"\"'"
    return None


def _bare_quote_after(raw: str, k: int) -> bool:
    # True if the first non-blank char at/after k in raw is a bare quote (not
    # preceded by a '&'/'^' sigil, which would land on the sigil instead).
    while k < len(raw) and raw[k] in " \t":
        k += 1
    return k < len(raw) and raw[k] in ("\"", "'")


def rule_p12a(raw: str, m: str) -> str | None:
    # find the call in masked (proves it's code), peek raw's first arg for a
    # bare quote — '&'/'^' prefix would land on '&'/'^', not the quote.
    for mo in _RE_P12A.finditer(m):
        if _bare_quote_after(raw, mo.end()):
            return "P12a: pass '&\"x\"' (StringName) not a bare string to this method"
    # decl site: typed StringName/NodePath = bare string → wants &"x" / ^"a/b".
    for mo in _RE_SN_DECL.finditer(m):
        if _bare_quote_after(raw, mo.end()):
            return "P12a: StringName init with a bare string — use '&\"x\"' (the annotation proves intent)"
    for mo in _RE_NP_DECL.finditer(m):
        if _bare_quote_after(raw, mo.end()):
            return "P12a: NodePath init with a bare string — use '^\"a/b\"' (the annotation proves intent)"
    return None


# H4 (CORRECT, #110573): a signal declared with untyped params can't be
# connect()-checked against the handler — typed params surface arity/type
# mismatch at connect time. Single-line decl; flag if any non-empty param lacks
# a ':'. 'signal foo' / 'signal foo()' (no params) are fine.
_RE_SIGNAL_DECL = re.compile(r"^\s*signal\s+\w+\s*\(([^)]*)\)")


def rule_h4(raw: str, m: str) -> str | None:
    mo = _RE_SIGNAL_DECL.match(m)
    if mo is None:
        return None
    params = mo.group(1).strip()
    if params == "":
        return None
    for part in params.split(","):
        if part.strip() != "" and ":" not in part:
            return "H4: type the signal params — 'signal foo(a: T, b: U)' (untyped params can't be connect-checked, #110573)"
    return None


def rule_s6(raw: str, m: str) -> str | None:
    if _RE_ARRAY_PRIM.search(m):
        return "S6: prefer Packed*Array over Array[primitive] (3-5x iter, no Variant boxing) — unless elements truly need Variant"
    return None


def rule_s6b(raw: str, m: str) -> str | None:
    if _RE_PACKED_CTOR.search(m):
        return "S6b: drop the Packed*Array() / Packed*Array([...]) constructor — assign a bare literal ([] or [1, 2, 3]); the typed annotation converts"
    return None


def rule_l1(raw: str, m: str) -> str | None:
    if _RE_RANGE_SIZE.search(m):
        return "L1: iterate directly ('for x in coll') not range(coll.size()) — measured ~1.3x faster + clearer; range only when you need the index"
    return None


def rule_l3(raw: str, m: str) -> str | None:
    mo = _RE_FOR_RANGE.search(m)
    if mo is None:
        return None
    args = _range_args(m, mo.end() - 1)         # mo.end()-1 = the '('
    if args is None:
        return None
    args = [a.strip() for a in args]
    # 1-arg range(N): count loop → for i: int in N. range(coll.size()) is L1's
    # job (iterate the collection), so skip it here.
    if len(args) == 1 and not args[0].endswith(".size()"):
        return "L3: count loop → 'for i: int in N' idiom (style; NOT a perf win — measured break-even; C14 is a typing concern not loop speed — see tests/gd-lint/BENCH.md)"
    # 2-arg range(0, N): start is 0 → also a count loop.
    if len(args) == 2 and args[0] == "0":
        return "L3: count loop → 'for i: int in N' idiom (style; NOT a perf win — measured break-even; see tests/gd-lint/BENCH.md)"
    return None


def rule_c3(raw: str, m: str) -> str | None:
    if _RE_C3_FILTER.search(m):
        return "C3: typed Array assigned from .filter()/.map() — these return an untyped Array (#72566); use 'x.assign(coll.filter(...))'"
    return None


def rule_c14(raw: str, m: str) -> str | None:
    if _RE_C14_RANGE.search(m):
        return "C14: typed Array assigned from range() — range() returns an untyped Array (#110659); use 'x.assign(range(...))' or iterate"
    return None


def rule_p22(raw: str, m: str) -> str | None:
    mo = _RE_P22.search(m)
    if mo is not None:
        fn = mo.group(1)
        return f"P22: float math → '{fn}f()' not '{fn}()' — untyped variant forces Variant dispatch (~1.3x; see BENCH.md)"
    return None


def rule_c11(raw: str, m: str) -> str | None:
    if _RE_SORT_CUSTOM_LAMBDA.search(m) and _RE_NONSTRICT_CMP.search(m):
        return "C11: sort_custom comparator must be a STRICT '<'/'>' — '<='/'>=' returns true on equal elements, breaking the strict-weak-ordering contract (#58878) → unstable/wrong sort"
    return None


def rule_p6(raw: str, m: str) -> str | None:
    if _RE_POP_FRONT.search(m):
        return ("P6: Array.pop_front()/pop_at(0) is O(n) — head removal shifts every element (#45455); "
                "a drain loop (pop_front until empty) is O(n^2). Measured 4.8.dev (BENCH.md): pop_front-draining "
                "~10k elements = ~10 ms (~60% of a 16.7 ms frame), ~13k = a whole frame; pop_back / index / swap-back "
                "are all O(n) and stay sub-millisecond at 10k. Tens of elements off the hot path are free. "
                "Fix: pop_back() (order flips), an index cursor (no mutation), or swap-with-last + pop_back for "
                "O(1) remove-at-index when order doesn't matter")
    return None


LINE_RULES: dict[str, object] = {
    "H1": rule_h1,
    "H2": rule_h2,
    "H4": rule_h4,
    "S1": rule_s1,
    "C1": rule_c1,
    "C3": rule_c3,
    "C14": rule_c14,
    "C11": rule_c11,
    "S6": rule_s6,
    "S6b": rule_s6b,
    "S15": rule_s15,
    "P12a": rule_p12a,
    "P22": rule_p22,
    "P6": rule_p6,
    "L1": rule_l1,
    "L3": rule_l3,
}

# Advisory rules: surfaced but NOT edit-blocking. The loop-idiom rules (L1/L2/L3)
# and P22 are perf/style-motivated; benchmarking (tests/gd-lint/BENCH.md)
# confirmed L1 (~1.3x) and P22 (~1.3x) but L1 carries FP and P22 can't tell
# float from int — both advise, never block. L2/L3 are style only (perf
# refuted). Promote out of this set only on a measured >=1.3x win + ~0 FP.
ADVISORY: set[str] = {"L1", "L2", "L3", "P22", "P6", "H14", "H13", "S11"}

# Category per rule: CORRECT (bug / wrong result), PERF (speed), STYLE (idiom).
CATEGORY: dict[str, str] = {
    "C1": "CORRECT", "C3": "CORRECT", "C9": "CORRECT", "C14": "CORRECT",
    "C11": "CORRECT", "M1": "CORRECT", "H4": "CORRECT", "H13": "CORRECT",
    "H1": "PERF", "H2": "PERF", "S6": "PERF", "D7b": "PERF", "P12a": "PERF",
    "L1": "PERF", "L2": "PERF", "P22": "PERF", "P6": "PERF", "H14": "PERF",
    "S11": "PERF",
    "S1": "STYLE", "S6b": "STYLE", "S15": "STYLE", "L3": "STYLE",
}


# ---- block rule: D7b value-only match ----------------------------------------

_RE_MATCH = re.compile(r"^(\s*)match\s+\S.*:\s*$")
# A pattern arm is "real pattern matching" (keep match) if it binds or
# destructures. These tokens disqualify the D7b flag.
_RE_PATTERN_MATCHING = re.compile(r"(\bvar\s|\[|\]|\{|\}|\.\.)")


def _indent(s: str) -> int:
    return len(s) - len(s.lstrip())


def find_value_only_matches(masked: list[str]) -> list[tuple[int, str]]:
    """Flag each 'match' whose every arm is a plain value compare (no binding,
    no destructure). Such dispatch belongs in if/elif (D7b). Conservative: any
    pattern-matching arm, or zero classifiable arms, leaves the match alone.
    """
    out: list[tuple[int, str]] = []
    n = len(masked)
    i = 0
    while i < n:
        mo = _RE_MATCH.match(masked[i])
        if mo is None:
            i += 1
            continue
        match_indent = len(mo.group(1))
        arm_indent: int | None = None
        value_arms = 0
        has_pattern_matching = False
        saw_arm = False
        j = i + 1
        scanned = 0
        while j < n and scanned < MAX_MATCH_ARMS:
            line = masked[j]
            if line.strip() == "":
                j += 1
                continue
            ind = _indent(line)
            if ind <= match_indent:
                break                       # block ended
            if arm_indent is None:
                arm_indent = ind            # first arm sets the arm column
            if ind != arm_indent:
                j += 1                      # arm body / nested block line
                continue
            # this line is an arm pattern
            saw_arm = True
            scanned += 1
            pattern = line.split(":", 1)[0]
            if _RE_PATTERN_MATCHING.search(pattern):
                has_pattern_matching = True
            elif pattern.strip() not in ("_", ""):
                value_arms += 1
            j += 1
        if saw_arm and not has_pattern_matching and value_arms >= 1:
            out.append((i, "D7b: value-only 'match' → if/elif (~5x dispatch overhead, even cold paths)"))
        i = max(j, i + 1)
    return out


def find_descending_while(masked: list[str]) -> list[tuple[int, str]]:
    """Flag a manual descending COUNTER `while v >= N: ... v -= K` — a
    `for i in range(hi, lo, -1)` is measured ~2x faster (BENCH.md, L2 advisory).
    Requires a numeric guard AND a literal decrement of the same var so value
    drains (while health > 0: health -= damage) are left alone.
    """
    out: list[tuple[int, str]] = []
    n = len(masked)
    i = 0
    while i < n:
        mo = _RE_WHILE_DESC.match(masked[i])
        if mo is None:
            i += 1
            continue
        indent = len(mo.group(1))
        var = mo.group(2)
        dec = re.compile(r"\b" + re.escape(var) + r"\s*-=\s*\d+\b")
        j = i + 1
        scanned = 0
        while j < n and scanned < MAX_MATCH_ARMS:
            line = masked[j]
            if line.strip() == "":
                j += 1
                continue
            if _indent(line) <= indent:
                break                           # block ended
            scanned += 1
            if dec.search(line):
                out.append((i, "L2: descending counter via 'while' → 'for i in range(hi, lo, -1)' (measured ~2x faster than manual while; see tests/gd-lint/BENCH.md)"))
                break
            j += 1
        i += 1
    return out


# H14 (advisory PERF): a parenthesized cast `(x as T)` inside a block already
# narrowed by `if x is T:` is redundant — `is` narrowed x to T, so the `as` only
# adds a Variant round-trip (style.md H14). Conservative on two axes: (1) the
# guard must be EXACTLY `if <id> is <Type>:` (compound conditions like
# `if x is T and ...:` are skipped — narrowing still holds but the tight match
# keeps FP at zero); (2) only the PARENTHESIZED cast is flagged — a binding
# `var y: T = x as T` has no parens and is the one form H14 explicitly allows
# ("only `as` when binding to new var"). Same id + same Type required.
_RE_IF_IS = re.compile(r"^(\s*)if\s+([A-Za-z_]\w*)\s+is\s+([A-Za-z_]\w*)\s*:\s*$")


def find_redundant_as_after_is(masked: list[str]) -> list[tuple[int, str]]:
    """Flag `(x as T)` within the body of an `if x is T:` block — the `is`
    already narrowed x to T, so the inline cast is a wasted Variant round-trip
    (H14). Scoped to the true-branch (indent > the `if`'s) and to the exact
    id+Type pair; bounded by MAX_MATCH_ARMS lines per block (NASA-2).
    """
    out: list[tuple[int, str]] = []
    n = len(masked)
    i = 0
    while i < n:
        mo = _RE_IF_IS.match(masked[i])
        if mo is None:
            i += 1
            continue
        indent = len(mo.group(1))
        var = mo.group(2)
        typ = mo.group(3)
        cast = re.compile(r"\(\s*" + re.escape(var) + r"\s+as\s+" + re.escape(typ) + r"\s*\)")
        j = i + 1
        scanned = 0
        while j < n and scanned < MAX_MATCH_ARMS:
            line = masked[j]
            if line.strip() == "":
                j += 1
                continue
            if _indent(line) <= indent:
                break                           # true-branch ended (dedent)
            scanned += 1
            if cast.search(line):
                out.append((j, "H14: redundant '(%s as %s)' — 'if %s is %s:' already narrowed it; drop the cast (adds a Variant round-trip)" % (var, typ, var, typ)))
            j += 1
        i += 1
    return out


# M1 (CORRECT): `await` inside `_ready()` pauses the node's initialization at an
# unpredictable point — children may be half-set-up, the parent's _ready hasn't
# run, signals wired in _ready aren't connected yet. Use call_deferred() or a
# separate coroutine kicked off from _ready (type-async.md M1). Block-scanned:
# any `await` at deeper indent than the `func _ready(` header belongs to its body
# (GDScript has no nested named funcs; an inline lambda there is S1's problem and
# still runs in the _ready frame). `await` elsewhere is fine — only _ready gated.
_RE_FUNC_READY = re.compile(r"^(\s*)func\s+_ready\s*\(")
_RE_AWAIT = re.compile(r"\bawait\b")


def find_await_in_ready(masked: list[str]) -> list[tuple[int, str]]:
    """Flag every `await` in the body of `func _ready()` (M1). Scoped to the
    _ready block by indent; bounded by MAX_MATCH_ARMS lines (NASA-2)."""
    out: list[tuple[int, str]] = []
    n = len(masked)
    i = 0
    while i < n:
        mo = _RE_FUNC_READY.match(masked[i])
        if mo is None:
            i += 1
            continue
        indent = len(mo.group(1))
        j = i + 1
        scanned = 0
        while j < n and scanned < MAX_MATCH_ARMS:
            line = masked[j]
            if line.strip() == "":
                j += 1
                continue
            if _indent(line) <= indent:
                break                           # _ready body ended (dedent)
            scanned += 1
            if _RE_AWAIT.search(line):
                out.append((j, "M1: no 'await' in _ready() — it pauses init at an unpredictable point; use call_deferred() or a separate coroutine"))
            j += 1
        i = max(j, i + 1)
    return out


# S11 (advisory PERF): `print()` is synchronous I/O — cheap once (~0.68 µs/call,
# BENCH.md), but in a per-frame callback it fires 60×/s and the cost is real.
# The broad "no ungated print" form is unenforceable (a `print` gated behind a
# debug flag is indistinguishable from an ungated one on one line → FP on every
# legit debug print). Tightened to the one shape where print is provably wrong
# regardless of gating: inside `_process`/`_physics_process`/`_draw`. Block-scan
# by indent (like M1). Outside those callbacks, not flagged — that's the
# reviewer's judgment call. Advisory: a `print` deliberately gated behind a debug
# flag *inside* _process is rare but legit, so surface, never block.
_RE_FUNC_PERFRAME = re.compile(r"^(\s*)func\s+_(?:physics_process|process|draw)\s*\(")
_RE_PRINT = re.compile(r"\b(?:print|prints|printt|printraw|print_rich|print_debug|printerr)\s*\(")


def find_print_in_perframe(masked: list[str]) -> list[tuple[int, str]]:
    """Flag every print-family call in the body of a per-frame callback (S11).
    Scoped to the callback block by indent; bounded by MAX_MATCH_ARMS (NASA-2)."""
    out: list[tuple[int, str]] = []
    n = len(masked)
    i = 0
    while i < n:
        mo = _RE_FUNC_PERFRAME.match(masked[i])
        if mo is None:
            i += 1
            continue
        indent = len(mo.group(1))
        j = i + 1
        scanned = 0
        while j < n and scanned < MAX_MATCH_ARMS:
            line = masked[j]
            if line.strip() == "":
                j += 1
                continue
            if _indent(line) <= indent:
                break                           # callback body ended (dedent)
            scanned += 1
            if _RE_PRINT.search(line):
                out.append((j, "S11: print() in a per-frame callback — synchronous I/O every frame; gate behind a debug flag or remove"))
            j += 1
        i = max(j, i + 1)
    return out


# C9: redefining an engine method shadows its behavior (silent collision).
# OBJECT_METHODS exist on every Object; NODE_METHODS only on Node-derived, so
# they are applied only when the script extends a Node-ish base — a domain
# `func get_name()` on a RefCounted is legitimate and not flagged.
_RE_EXTENDS = re.compile(r"^\s*extends\s+(\w+)")
_RE_FUNC_DEF = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(")
_NON_NODE_BASES = {"RefCounted", "Resource", "Object"}
_OBJECT_METHODS = {
    "get_class", "is_class", "get_instance_id", "get_rid",
    "get_meta", "set_meta", "has_meta", "get_script", "set_script",
    "has_method", "has_signal", "get_method_list", "get_property_list",
    "get_signal_list",
}
_NODE_METHODS = {
    "get_name", "set_name", "get_path", "get_owner", "set_owner",
    "get_parent", "get_node", "get_node_or_null", "get_index", "get_tree",
    "get_groups", "is_inside_tree", "queue_free", "is_queued_for_deletion",
    "get_viewport", "get_window", "find_child", "find_children",
    "get_children", "get_child", "get_child_count", "replace_by", "get_path_to",
}


def find_reserved_overrides(masked: list[str]) -> list[tuple[int, str]]:
    base = ""
    for line in masked[:20]:                     # bounded scan for the extends
        em = _RE_EXTENDS.match(line)
        if em is not None:
            base = em.group(1)
            break
    node_like = base != "" and base not in _NON_NODE_BASES
    reserved = _OBJECT_METHODS | _NODE_METHODS if node_like else _OBJECT_METHODS
    out: list[tuple[int, str]] = []
    for idx, line in enumerate(masked):
        fm = _RE_FUNC_DEF.match(line)
        if fm is not None and fm.group(1) in reserved:
            out.append((idx, "C9: 'func %s()' shadows a reserved Node/Object method — rename (silent collision with engine behavior)" % fm.group(1)))
    return out


# H13 (advisory CORRECT): duck-typed dispatch — `obj.has_method(&"x")` guarding
# an `obj.call(&"x", ...)` has zero compile-time guarantees: a typo, an arity
# drift, or a wrong arg type all silently no-op, and `call()` returns Variant
# (a missing-method null narrows to 0 on `as int`). Two+ bodies sharing behavior
# → a common base class, dispatch via `is` (style.md H13). Flagged only when the
# SAME literal name appears in both a has_method() and a .call() in the file —
# the duck-dispatch smell, near-0 FP. Advisory (not blocking) because genuine
# reflection (save-system deserialization on unknown user scripts) is a cited
# legit exception; @tool scripts (editor reflection by design) are skipped whole.
_RE_HAS_METHOD_LIT = re.compile(r"\bhas_method\(\s*&?(\"|')([^\"']*)\1")
_RE_CALL_LIT = re.compile(r"\.call\(\s*&?(\"|')([^\"']*)\1")


def _code_lits(raw: str, m: str, rx: "re.Pattern[str]") -> list[tuple[int, str]]:
    # (start, literal) for each match whose call site is code (masked non-blank
    # at the match start), reading the literal name from raw (masked blanks it).
    out: list[tuple[int, str]] = []
    for mo in rx.finditer(raw):
        if mo.start() < len(m) and m[mo.start()] != " ":
            out.append((mo.start(), mo.group(2)))
    return out


def find_duck_dispatch(raw_lines: list[str], masked: list[str]) -> list[tuple[int, str]]:
    """Flag `has_method(&"X")` lines whose literal X is also used in a `.call("X")`
    somewhere in the file (H13). Skips @tool scripts wholesale (legit reflection).
    """
    for ln in raw_lines[:5]:
        if ln.lstrip().startswith("@tool"):
            return []
    call_names: set[str] = set()
    for idx, raw in enumerate(raw_lines):
        for _, name in _code_lits(raw, masked[idx], _RE_CALL_LIT):
            call_names.add(name)
    if not call_names:
        return []
    out: list[tuple[int, str]] = []
    for idx, raw in enumerate(raw_lines):
        for _, name in _code_lits(raw, masked[idx], _RE_HAS_METHOD_LIT):
            if name in call_names:
                out.append((idx, "H13: duck-typed dispatch — has_method(&\"%s\")+call(&\"%s\"); give the targets a common base class + dispatch via 'is' (typo/arity/type silently no-op)" % (name, name)))
                break
    return out


# ---- suppression -------------------------------------------------------------

_RE_IGNORE = re.compile(r"#\s*gdlint:\s*ignore(?:\[([A-Za-z0-9, ]+)\])?")


def suppressed(raw: str, rule: str) -> bool:
    mo = _RE_IGNORE.search(raw)
    if mo is None:
        return False
    scoped = mo.group(1)
    if scoped is None:
        return True                          # bare 'ignore' = all rules
    return rule in {r.strip() for r in scoped.split(",")}


def file_disabled(lines: list[str]) -> bool:
    head = lines[:5]
    return any("gdlint: disable-file" in ln for ln in head)


# ---- driver ------------------------------------------------------------------


def lint_file(path: str) -> list[tuple[str, str]]:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            raw_lines = fh.read().split("\n")
    except OSError:
        return []                            # unreadable → fail open
    if len(raw_lines) > MAX_LINES or file_disabled(raw_lines):
        return []
    masked = mask_code(raw_lines)
    findings: list[tuple[int, str, str]] = []   # (lineno, rule_id, msg)

    for idx, m in enumerate(masked):
        raw = raw_lines[idx]
        for rule_id, fn in LINE_RULES.items():
            msg = fn(raw, m)                 # type: ignore[operator]
            if msg is not None and not suppressed(raw, rule_id):
                findings.append((idx + 1, rule_id, msg))

    for line_idx, msg in find_value_only_matches(masked):
        if not suppressed(raw_lines[line_idx], "D7b"):
            findings.append((line_idx + 1, "D7b", msg))

    for line_idx, msg in find_descending_while(masked):
        if not suppressed(raw_lines[line_idx], "L2"):
            findings.append((line_idx + 1, "L2", msg))

    for line_idx, msg in find_await_in_ready(masked):
        if not suppressed(raw_lines[line_idx], "M1"):
            findings.append((line_idx + 1, "M1", msg))

    for line_idx, msg in find_redundant_as_after_is(masked):
        if not suppressed(raw_lines[line_idx], "H14"):
            findings.append((line_idx + 1, "H14", msg))

    for line_idx, msg in find_reserved_overrides(masked):
        if not suppressed(raw_lines[line_idx], "C9"):
            findings.append((line_idx + 1, "C9", msg))

    for line_idx, msg in find_duck_dispatch(raw_lines, masked):
        if not suppressed(raw_lines[line_idx], "H13"):
            findings.append((line_idx + 1, "H13", msg))

    for line_idx, msg in find_print_in_perframe(masked):
        if not suppressed(raw_lines[line_idx], "S11"):
            findings.append((line_idx + 1, "S11", msg))

    findings.sort(key=lambda f: (f[0], f[1]))
    # Format: 'path:line: RULE [CATEGORY]: body [advisory]'. Messages embed a
    # leading 'RULE: ' — strip it so the id isn't doubled. Advisory tag lets the
    # gate split blocking from advisory.
    out: list[tuple[str, str]] = []
    for ln, rid, msg in findings:
        cat = CATEGORY.get(rid, "?")
        body = msg[len(rid) + 2:] if msg.startswith(rid + ": ") else msg
        tag = " [advisory]" if rid in ADVISORY else ""
        out.append((rid, f"{path}:{ln}: {rid} [{cat}]: {body}{tag}"))
    return out


def main(argv: list[str]) -> int:
    try:
        blocking = False
        for path in argv[1:]:
            for rid, line in lint_file(path):
                print(line)
                if rid not in ADVISORY:
                    blocking = True
        # exit 1 only when a BLOCKING finding exists; advisory-only → exit 0
        # (printed, but the gate won't block on it).
        return 1 if blocking else 0
    except Exception:                        # noqa: BLE001 — fail open, never wedge edits
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
