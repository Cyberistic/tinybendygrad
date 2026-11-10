#!/usr/bin/env python3
"""ban-marks.py -- **THE LINT THAT BANS ` ` AND `**` FROM THE TREE's COMMENTS.**

    .venv/bin/python .agents/slop/loc/ban-marks.py            # the census
    .venv/bin/python .agents/slop/loc/ban-marks.py --check    # rc=1 if any hit

**WHAT IT BANS, AND WHY EACH IS BANNED:**

  * **` ` (U+21D2) IN A COMMENT.** IT IS THE TREE's OLD ARROW STYLE, AND **IT IS THE
    ARROW THAT MAKES A COMMENT LINE EXPENSIVE**: THE `**AND ... **` CHAIN STYLE PACKS A
    WHOLE PARAGRAPH INTO ONE LINE AND MAKES THE COMMENT **UNREADABLE AT A GLANCE**.
    **MEASURED 2026-11-10: THE PORT's COMMENT BLOCKS HOLD **1,139,461 WORDS** IN 100,588
    LINES -- 11.3 WORDS PER LINE -- **AND THE ` ` STYLE IS WHAT PRODUCES THAT DENSITY.**
  * **`**` (DOUBLE ASTERISK) IN A COMMENT.** IT IS **THE EMPHASIS MARKER**, AND **THE
    TREE's OWN STYLE HAS IT ON **EVERY** PROSE LINE** -- **MEASURED 2026-11-10: THE
    COMMENT BLOCKS CARRY **5,882** ALL-CAPS LINES AND THE `**` MARKER IS WHAT MAKES THEM
    ALL-CAPS.** **IT IS **THE EMPHASIS**, AND EMPHASIS ON EVERY LINE IS NO EMPHASIS.**
  * **MORE THAN FIVE ALL-CAPS WORDS IN **ONE** COMMENT LINE.** **ALL-CAPS IS **THE
    TREE's OLD EMPHASIS**, **AND A LINE THAT SHOUTS **SIX** WORDS IS NOT EMPHASIS, IT IS A
    PARAGRAPH IN CAPS.** **MEASURED 2026-11-10: THE COMMENT BLOCKS CARRY **5,882** ALL-CAPS
    LINES** AND **THE PORT's `uop/symbolic.bend` HAS **306** MARKED LINES** -- **AND A
    READER CANNOT SCAN A LINE OF SHOUTED WORDS.**

**AND THE ALL-CAPS RULE IS **PER LINE**, NOT PER BLOCK** -- **BECAUSE A BLOCK OF SHOUTED
LINES IS **THE **SAME** PROBLEM** AND **A LINE-BY-LINE RULE IS THE ONE THAT CAN BE
CHECKED.**

**AND WHAT IT **NEVER** BANS: **THE MARKERS ARE ONLY BANNED IN COMMENTS** -- **A `**`
OR A ` ` IN **CODE** IS A DIFFERENT THING** AND IS **NOT** THIS LINT's BUSINESS.**
**AND IT **DOES NOT** BAN **THE .md FILES' PROSE** -- **ONLY **THE SOURCE's COMMENTS**,
**AND THE REASON IS THAT THE .md FILES ARE **DOCUMENTATION** AND THE COMMENTS ARE **THE
CODE**.**

**AND THE POPULATION IS **A DIRECTORY WALK** -- **`os.walk` + `endswith`**, **NEVER
`glob`** (WHICH RETURNS `[]` WHEN `.bend` FILES ARE ON DISK) -- **AND IT COVERS
`tinybendygrad/`, `gates/`, `checks/`, `oracles/` AND `examples/`.**
"""

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# **THE SOURCE DIRS** -- **AND THE PORT IS THE MAIN ONE.**
DIRS = ("tinybendygrad", "gates", "checks", "oracles", "examples")
SUFFIXES = (".bend", ".py", ".js", ".mjs", ".c", ".sh")
ARROW = "⇒"
STAR = "**"
# **THE ALL-CAPS WORD** -- **A WORD OF **THREE OR MORE** LETTERS** THAT IS **ALL UPPERCASE**
# **AND **IS NOT A **TYPE**-LIKE NAME** -- **AND THE TYPE-LIKE NAMES ARE **THE **CODE's**
# (`UOp`, `CMPEQ`, `Ops`), **SO THEY ARE EXEMPT** OR **EVERY LINE WOULD COUNT THEM.**
CAPS_WORD = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
# **THE **EXEMPT** NAMES** -- **THE TYPE-LIKE ONES THE CODE ITSELF USES.**
EXEMPT = {
    "UOp", "Ops", "CMPEQ", "CMPLT", "CMPNE", "ADD", "MUL", "SUB", "DIV", "MOD", "CONST",
    "SPEC", "CAST", "PARAM", "BUFFER", "RANGE", "INDEX", "WHERE", "STORE", "LOAD", "NULL",
    "BOOL", "INT", "FLOAT", "NONE", "TRUE", "FALSE", "AND", "OR", "NOT", "IF", "ELSE",
    "TODO", "WARN", "INFO", "DEBUG", "ERROR", "NOTE", "FIXME", "XXX", "HACK",
}
MAX_CAPS = 5


def walk() -> list[Path]:
    """**A DIRECTORY WALK, NEVER `glob`.**"""
    out = []
    for d in DIRS:
        for base, _dirs, files in os.walk(ROOT / d):
            for f in files:
                if f.endswith(SUFFIXES):
                    out.append(Path(base) / f)
    return sorted(out)


def is_exponent(body: str) -> bool:
    """**EVERY `**` IN **THE LINE** IS **AN EXPONENT** -- **MEASURED 2026-11-10:
    `tinybendygrad/uop/fold.bend:86` READS "`uint64.max` = 2**64-1", **AND THAT IS **REAL
    PYTHON** IN A COMMENT**, **AND THE EMPHASIS MARKER **AND** THE EXPONENT OPERATOR ARE
    **THE SAME TWO CHARACTERS** -- **SO THE BAN MUST TELL THEM APART**."""
    import re as _re
    return all(
        body[m.start() - 1].isdigit() and body[m.end()].isdigit()
        for m in _re.finditer(r"\*\*", body)
    )


def caps_words(body: str) -> list[str]:
    """**THE ALL-CAPS WORDS OF **ONE** COMMENT LINE, **EXCLUDING THE TYPE-LIKE ONES**."""
    return [w for w in CAPS_WORD.findall(body) if w not in EXEMPT]


def hits(path: Path) -> list[tuple[int, str, str]]:
    """**(LINE NO, WHICH MARK, THE LINE).**"""
    out = []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return out
    for i, l in enumerate(lines):
        s = l.strip()
        if not s.startswith("#"):
            continue
        body = s.lstrip("#").strip()
        if ARROW in body:
            out.append((i + 1, "ARROW", s))
        if STAR in body and not is_exponent(body):
            out.append((i + 1, "STAR", s))
        cw = caps_words(body)
        if len(cw) > MAX_CAPS:
            out.append((i + 1, f"CAPS{len(cw)}", s))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--show", type=int, default=0, help="print N sample hits")
    args = ap.parse_args()
    total = 0
    per_kind = {"ARROW": 0, "STAR": 0, "CAPS": 0}
    samples = []
    for p in walk():
        h = hits(p)
        if not h:
            continue
        total += len(h)
        for _n, kind, _s in h:
            per_kind["CAPS" if kind.startswith("CAPS") else kind] += 1
        if len(samples) < args.show:
            samples.extend((p.relative_to(ROOT), n, k, s) for n, k, s in h[: args.show])
    for p, n, k, s in samples:
        print(f"  {p}:{n} [{k}] {s[:90]}")
    print(f"  ARROW: {per_kind['ARROW']}   STAR: {per_kind['STAR']}   CAPS>{MAX_CAPS}: {per_kind['CAPS']}   TOTAL: {total}")
    if args.check:
        return 1 if total else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
