#!/usr/bin/env python3
"""FIX THE **HEAD TABLE's** TWO BARS THAT DISAGREE WITH THEIR OWN SECTIONS.

**WHY THE HEAD TABLE AND NOT THE SUMMARY TABLE.** THE SUMMARY TABLE's BARS ARE CORRECT --
`.agents/slop/todo-sweep2/twotables.py` MEASURED **0 STALE** AND **0 AHEAD** AGAINST IT,
AFTER THE FOUR `**NOT COMMITTED.**` SECTIONS WERE RESOLVED **BY POSITION** (THEIR THREE BARS
ARE 7/7, 11/11 AND 9/9 AND ALL THREE ARE RIGHT). **THE HEAD TABLE IS THE ONE THAT HAS
DRIFTED**, AND IT IS THE TABLE A READER MEETS FIRST.

**THE TWO FIXES, AND WHAT EACH IS EVIDENCE FOR.**

  `arena-aliasing`  `2/10` -> `8/8`
    THE SECTION `## ARENA ALIASING SWEEP` HAS **8** ITEMS AND **ALL 8 ARE TICKED** (MEASURED),
    AND ITS OWN SUB-HEADING IS `### ✅ CLOSED`. **THE BAR WAS A ROW THAT COULD NOT GO RED.**
    **AND THE SUMMARY TABLE ALREADY SAID `██████████ 8/8 100%` -- SO THE LEDGER SAID TWO
    THINGS ABOUT ONE FACT, AND THE ONE A READER MEETS FIRST WAS THE WRONG ONE.**

  `lane-liveness`  `11/11` -> `13/15`
    THE SECTION `### Lane liveness` HAS **13** TICKED AND **2 OPEN** (MEASURED), AND THE TWO
    OPEN ONES ARE **REAL AND PORT-SIDE**: `dtype.bend` ("A PORT DEFECT AND IS NOT MINE TO
    FIX") AND `codegen/decomp/dtype.bend`'s `BASE_ORACLES` lane ("Named to the owning unit").
    **THE BAR SAID 11/11 WHILE THE SECTION CARRIED TWO OPEN ITEMS -- WHICH IS THE WORSE
    HALF: A LEDGER THAT PROMISES A COMPLETION THAT IS NOT THERE.**

**AND THE DENOMINATOR CHANGES FROM 11 TO 15, NOT FROM 11 TO 13, BECAUSE A BAR's
DENOMINATOR IS EVERY ITEM IN THE CATEGORY AND TWO ITEMS WERE ADDED AFTER THE BAR WAS
WRITTEN.** A BAR THAT COUNTS ONLY THE TICKED ITEMS IS A PERCENTAGE, NOT A FRACTION.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/patch_bars.py <target-todo.md>
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# (the row's own first LINE, the row's own REPLACEMENT first line)
ROWS = [
    (
        "arena-aliasing   [##........] 2/10",
        "8/8",
    ),
    (
        "lane-liveness   [###########] 11/11",
        "13/15",
    ),
]


def main():
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else (ROOT / ".agents/TODO.md")
    lines = target.read_text().split("\n")
    applied = 0
    for old, new in ROWS:
        hits = [i for i, l in enumerate(lines) if l.startswith(old)]
        if len(hits) != 1:
            print(f"SKIP (found {len(hits)}): {old[:50]}")
            continue
        i = hits[0]
        # THE BAR IS THE HEAD TABLE's ONE LINE: `name  [bar] n/d  prose`. **THE BAR's
        # WIDTH MUST MATCH ITS DENOMINATOR**, so the replacement's BAR IS BUILT FROM THE NEW
        # FRACTION rather than typed, and the old line's TAIL (everything after `n/d`) is
        # KEPT VERBATIM -- the prose is another unit's to write.
        m = re.match(r"^(\S+)(\s+)(\[[#\.]+\])(\s+)(\d+/\d+)(.*)$", lines[i])
        assert m, lines[i]
        name, gap, _bar, gap2, _frac, tail = m.groups()
        # **THE NEW FRACTION COMES FROM THE ROW's OWN `new` TEXT, NOT FROM THE MATCHED
        # LINE.** The first version of this script took `d, dd` FROM THE MATCHED LINE, so it
        # REBUILT THE SAME FRACTION AND THE PATCH WAS A NO-OP THAT REPORTED SUCCESS -- which
        # is the shape where an instrument says it did a thing and did nothing.
        d, dd = (int(x) for x in new.split()[-1].split("/"))
        # **THE ICON IS NOT A FRACTION BAR, AND MEASURING THAT IS WHAT LET THIS PATCH BE
        # CORRECT.** OVER ALL **151** HEAD-TABLE ROWS: **102** ARE AT 100% AND **100** OF
        # THOSE HAVE A **FULL** ICON; AND AMONG THE **49** THAT ARE NOT AT 100%, THE ICON's
        # FILL IS THE NUMERATOR IN ONLY **26**. **SO THE ICON IS A FIXED-WIDTH PROGRESS
        # ICON WHOSE ONLY RULE IS "**FULL AT 100%**", AND THE **FRACTION `n/d` IS THE ONLY
        # PRECISE PART.** THE FIRST VERSION OF THIS SCRIPT REBUILT THE ICON AT THE NEW
        # DENOMINATOR's WIDTH, WHICH RESIZED THE TABLE's ALIGNMENT AND PRINTED
        # `[########..]` (8 OF 10) FOR A ROW THAT SAYS `8/8` -- **A BAR THAT DISAGREES WITH
        # ITS OWN FRACTION IN THE SAME TOKEN.**
        #
        # **SO: THE ICON's WIDTH IS THE OLD ICON's WIDTH (the field's alignment), AND THE
        # ICON IS FULL WHEN THE FRACTION IS 100%.**
        width = len(_bar) - 2
        fill = width if d >= dd else min(d, width)
        bar = "[" + "#" * fill + "." * (width - fill) + "]"
        lines[i] = f"{name}{gap}{bar}{gap2}{d}/{dd}{tail}"
        applied += 1
        print(f"  L{i+1}: {lines[i][:76]}")
    target.write_text("\n".join(lines))
    print(f"patched {applied} bars in {target}")


if __name__ == "__main__":
    main()
