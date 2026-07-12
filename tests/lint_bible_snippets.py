#!/usr/bin/env python3
"""Lint the lint-enforced GDScript snippets embedded in the bible markdown.

The bible's inline ```gdscript code blocks were drifting from the bible's own
rules (untyped params, `:=`, untyped `for`) because nothing checked them — they
are prose, not files. This harness closes that gap: it extracts every fenced
gdscript block, splits it into polarity-tagged segments, and runs gd-lint.py on
the lint-enforced ones. A finding there fails the run — the bible follows its
own rules.

NOT a parser. gd-lint.py is a text linter (regex over masked text), so it lints
fragments fine — undefined types, `...` elisions, missing `extends` don't matter.

UNIFIED SNIPPET STYLE (the one signal — no prose scanning, no keyword guessing).
Each fence, or each segment within a mixed fence, opens with a polarity header:

    # Good — <why>   lint-enforced (must pass)
    # Or   — <why>   a good alternative — lint-enforced
    # Bad   — <why>  anti-pattern — NOT enforced
    # Repro — <why>  engine-bug repro — NOT enforced
    # Naive — <why>  the strawman before a refactor — NOT enforced

An UNTAGGED segment defaults to lint-enforced (the fail-safe: forget to tag bad
code → the run FAILS, prompting the tag; it never silently skips). So authors
tag only the *bad* code; good code needs no ceremony. A fence that genuinely
can't be linted opts out with a `# snippet-lint: skip` line.

Usage:  lint_bible_snippets.py BIBLE_DIR [GDLINT]
Exit:   1 if any lint-enforced segment trips gd-lint, else 0.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_FILES = 1000
FENCE = re.compile(r"^```g?d?script\s*$")  # ```gdscript / ```gd / ```
FENCE_OPEN = re.compile(r"^```gdscript\s*$")
FENCE_CLOSE = re.compile(r"^```\s*$")

# UNIFIED SNIPPET STYLE. Every fenced gdscript block — or each segment within a
# mixed fence — declares its polarity with a leading comment header:
#
#   # Good — <why>   lint-enforced (must pass gd-lint)
#   # Or   — <why>   a good alternative — lint-enforced
#   # Bad   — <why>  an anti-pattern — NOT enforced (it's meant to violate)
#   # Repro — <why>  an engine-bug repro — NOT enforced
#   # Naive — <why>  the strawman before a refactor — NOT enforced
#
# An UNTAGGED segment defaults to GOOD (must lint). This is the fail-safe: forget
# to tag a bad block and the harness FAILS loudly, prompting the tag — it never
# silently skips. Authors tag the *bad* code; good code needs no ceremony.
#
# Polarity is the ONLY signal — no prose scanning, no fuzzy keyword list. A fence
# that genuinely can't be linted (rare) opts out with `# snippet-lint: skip`.
_SKIP_WORDS = {"bad", "repro", "naive", "strawman"}
_SKIP = "snippet-lint: skip"
_HEADER = re.compile(
    r"^\s*#\s*(bad|repro|naive|strawman|good|or)\b", re.IGNORECASE
)


def split_segments(block: str) -> list[tuple[str | None, str, int]]:
    """Split a fence into (polarity, text, line_offset) at header comment lines.

    polarity: 'skip' (bad/repro/naive/strawman) or 'lint' (good/or) from the
    header word, or None for a leading segment with no header (setup code before
    the first header). line_offset is the segment's 0-based first line in block.
    """
    lines = block.split("\n")
    segs: list[tuple[str | None, str, int]] = []
    cur: list[str] = []
    cur_pol: str | None = None
    cur_off = 0
    for idx, ln in enumerate(lines):
        h = _HEADER.match(ln)
        if h:
            if cur:
                segs.append((cur_pol, "\n".join(cur), cur_off))
            cur = [ln]
            cur_off = idx
            cur_pol = "skip" if h.group(1).lower() in _SKIP_WORDS else "lint"
        else:
            if not cur:
                cur_off = idx
            cur.append(ln)
    if cur:
        segs.append((cur_pol, "\n".join(cur), cur_off))
    return segs


def extract_blocks(md: str) -> list[tuple[int, str]]:
    """Return (start_line_1based, block_text) per ```gdscript fence."""
    out: list[tuple[int, str]] = []
    lines = md.split("\n")
    i, n = 0, len(lines)
    while i < n:
        if FENCE_OPEN.match(lines[i]):
            start = i + 1
            body: list[str] = []
            i += 1
            while i < n and not FENCE_CLOSE.match(lines[i]):
                body.append(lines[i])
                i += 1
            out.append((start + 1, "\n".join(body)))
        i += 1
    return out


def good_targets(block: str) -> list[tuple[str, int]]:
    """(segment_text, line_offset) for each lint-enforced segment of a fence.

    Untagged fence → one must-lint unit. Tagged fence → split; 'lint' and
    pre-header (None) segments are enforced, 'skip' segments dropped.
    """
    if _SKIP in block.lower():
        return []
    segs = split_segments(block)
    if not any(p is not None for p, _, _ in segs):
        return [(block, 0)]                # untagged whole fence = must lint
    out: list[tuple[str, int]] = []
    for pol, text, off in segs:
        if pol == "skip" or text.strip() == "":
            continue
        out.append((text, off))            # 'lint' header or pre-header setup
    return out


def lint_block(gdlint: str, block: str) -> list[str]:
    with tempfile.NamedTemporaryFile(
        "w", suffix=".gd", delete=False, encoding="utf-8"
    ) as fh:
        fh.write(block + "\n")
        path = fh.name
    try:
        res = subprocess.run(
            [sys.executable, gdlint, path],
            capture_output=True, text=True, timeout=30,
        )
        # gd-lint prints 'path:line: RULE [CAT]: msg'; keep BLOCKING only
        # (advisory rides along but shouldn't fail the doc gate).
        findings = []
        for ln in res.stdout.splitlines():
            if ln.strip() and "[advisory]" not in ln:
                findings.append(ln.split(": ", 1)[-1])
        return findings
    finally:
        Path(path).unlink(missing_ok=True)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: lint_bible_snippets.py BIBLE_DIR [GDLINT]", file=sys.stderr)
        return 2
    bible = Path(argv[1])
    gdlint = argv[2] if len(argv) > 2 else str(bible.parent / "gd-lint.py")
    good_segs = no_good = fails = 0
    for md_path in sorted(bible.rglob("*.md"))[:MAX_FILES]:
        text = md_path.read_text(encoding="utf-8", errors="replace")
        for start, block in extract_blocks(text):
            targets = good_targets(block)
            if not targets:
                no_good += 1            # whole fence was Bad/repro/skip
                continue
            for seg_text, off in targets:
                good_segs += 1
                findings = lint_block(gdlint, seg_text)
                if findings:
                    fails += 1
                    print(f"FAIL {md_path.name}: good segment @ line {start + off}")
                    for f in findings:
                        print(f"      {f}")
    print("----")
    print(f"good segments linted: {good_segs}  "
          f"bad/skip fences: {no_good}  failing: {fails}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
