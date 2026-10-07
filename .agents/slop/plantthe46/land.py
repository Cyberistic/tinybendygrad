#!/usr/bin/env python3
"""LAND THE REFUSAL PLANT on the gates whose refusal sits above every `argparse`.

    .venv/bin/python .agents/slop/plantthe46/land.py            # dry run: what would change
    .venv/bin/python .agents/slop/plantthe46/land.py --write    # write it

WHY THIS IS A SCRIPT AND NOT SIX EDITS. Five of the six carry the SAME wrong sentence -- "At rest
this refuses on its swept input, so no plant reaches a code" -- and the sentence is false, because
rc 3 IS what the gate returns at rest. That is a declaration disagreeing with the program it
declares for, which is the defect `gates/gate-surface.py` exists to catch and this file feeds.
Six copies of one comment is six places to rot, so the text lives here and is written from here.

**A REFUSAL PLANT IS NOT A BOTH-WAYS PLANT, AND THE COMMENT SAYS SO.** `PLANTS[3] = []` proves the
refusal is REACHABLE. It cannot prove the gate DISTINGUISHES 3 from 0 -- no argv can reach 0 --
so every other code stays UNPLANTED and the instrument keeps it red. `.agents/slop/zerogate/
REPORT.md` §2(a) measured the geometry; this script only records what it found in the files that
carry the finding.

EDITS ONE CONSTANT PER FILE. No verdict is added, removed or renamed; `VERDICTS` is untouched.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]

BLOCK = """# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate.
#
# `PLANTS[3]` IS THE REFUSAL PLANT, and it is the only state argv can reach: this gate refuses at
# MODULE SCOPE, above every `argparse` -- the geometry is measured by
# `.agents/slop/plantthe46/unreach.py`, which imports this tree's own declaration reader by path --
# so no argument of any shape gets past it. `[]` therefore reaches `3`, and nothing else ever will.
# It proves the refusal is REACHABLE. It does NOT prove this gate can tell `3` from `0`, because no
# argv reaches `0`; every other code below stays UNPLANTED and the instrument keeps it red rather
# than this file claiming a plant it does not have.
VERDICTS = __VERDICTS__
PLANTS = {3: []}"""

STALE = re.compile(
    r"# THE VERDICT SURFACE, DECLARED\.[^\n]*\n"
    r"(?:# [^\n]*\n)*?"
    r"VERDICTS = (?P<v>\{[^\n]*\})\nPLANTS = \{\}\n", re.M)


def main():
    write = "--write" in sys.argv
    gs = importlib.util.spec_from_file_location("gs", ROOT / "gates" / "gate-surface.py")
    mod = importlib.util.module_from_spec(gs)
    gs.loader.exec_module(mod)
    changed = 0
    for p in sorted((ROOT / "checks").glob("*.py")) + sorted((ROOT / "gates").glob("*.py")):
        verdicts, plants, _ri, _n = mod.declaration(p)
        if verdicts is None or 3 not in verdicts or 3 in (plants or {}):
            continue
        src = p.read_text()
        m = STALE.search(src)
        if not m:
            print(f"  SKIP {p.relative_to(ROOT)}: declares 3, has no `PLANTS = {{}}` to replace")
            continue
        new = BLOCK.replace("__VERDICTS__", m.group("v"))
        out = src[:m.start()] + new + src[m.end():]
        print(f"  {'WRITE' if write else 'WOULD WRITE'} {p.relative_to(ROOT)}: "
              f"PLANTS {{}} -> {{3: []}}, and the stale sentence replaced")
        if write:
            p.write_text(out)
            changed += 1
    print(f"{'landed' if write else 'would land'} {changed} declaration(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())