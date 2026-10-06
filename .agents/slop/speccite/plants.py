#!/usr/bin/env python3
"""SPECCITE PLANTS. Three arms, and the tree is NEVER modified: each arm writes a variant of
`tinybendygrad/uop/spec.bend` into `plants/` and the gate is pointed at THAT.

    .venv/bin/python .agents/slop/speccite/plants.py

| arm | what it plants | what it must show |
|---|---|---|
| `CONTROL` | nothing -- the live bytes | GREEN, so RED below is the plant and not the harness |
| `PLANT-1`  | the real defect, verbatim from `git show HEAD:` | RED: `STALE-RULE` |
| `PLANT-2`  | a citation that is BYTE-TRUE and still wrong | GREEN: **the class this check cannot see** |
| `PLANT-3`  | a line number moved one line | `STALE-LINE`, and git is SILENT -- the belt's other arm |

**PLANT-2 IS THE POINT.** Its quote is on the line it names, in the file it names, verbatim. So the
gate's evidence is complete and its answer is "the citation holds" -- and the comment is false,
because `sh_23` also compares dtypes and `spec.py:113` does not. **THE EVIDENCE IS INVARIANT UNDER
THE VERY EDIT THAT BROKE IT**, because `ded106b18`/`ad117c928` deleted a CONJUNCT and left its
sibling in place. That is not a bug in this file; it is the answer to "can a static check decide
whether a citation's BEHAVIOUR still holds?" -- and it is no.

PLANT-3 exists because PLANT-1 alone would not prove independence: PLANT-1 is seen by the `git`
lane. PLANT-3 is seen by the substring lane and NOT by the git lane (`git log -S` on surviving
text is silent). Two methods, one regex between them, two different verdicts.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, "tinybendygrad/uop/spec.bend")
OUT = os.path.join(ROOT, ".agents/slop/speccite/plants")
GATE = os.path.join(ROOT, "checks/citation-gate.py")

# The real defect, from `git show HEAD:tinybendygrad/uop/spec.bend`, byte for byte.
BROKEN_ARG_CALL = """# `isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype` -- spec.py:113. The
# `isinstance` half is the arm; the `dtype is` half is the comparison below.
"""
# Byte-true, and false: the quote IS on spec.py:113; the claim that sh_23 IS that rule is not.
INVISIBLE = """# spec.py:113 `lambda x: isinstance(x.arg, CallInfo)` -- and sh_23 below is that
# rule, VERBATIM, dtype comparison included.
"""
FIXED = """# spec.py:113 `lambda x: isinstance(x.arg, CallInfo)` -- the WHOLE rule at HEAD. The
# x.dtype-is-x.arg.dtype conjunct was ADDED at 6f4bfde23 and REMOVED at ad117c928, so
# arg_call and sh_23.body are STRICTER THAN THE SPEC. Not retypable: AUTHORING.
"""


def gate(path: str) -> tuple[int, list[str]]:
    r = subprocess.run([sys.executable, GATE, path], cwd=ROOT, capture_output=True, text=True)
    rows = [ln.strip() for ln in r.stdout.splitlines() if ".bend:" in ln or ".py:" in ln]
    return r.returncode, rows


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    live = open(SRC, encoding="utf-8").read()
    arms = {
        "CONTROL": live,
        "PLANT-1": live.replace(FIXED, BROKEN_ARG_CALL),
        "PLANT-2": live.replace(FIXED, INVISIBLE),
        "PLANT-3": live.replace("-- spec.py:96. Only the length", "-- spec.py:97. Only the length"),
    }
    for n in ("PLANT-1", "PLANT-2", "PLANT-3"):
        if arms[n] == live:
            print(f"  {n} DID NOT MOVE: its anchor text is not in the file, so this arm proves NOTHING")
            return 2
    if arms["PLANT-1"] == live:
        print("  PLANT-1 DID NOT MOVE: the broken comment is not in the file it claims to plant into")
        return 2
    bad = 0
    for name, text in arms.items():
        p = os.path.join(OUT, "spec.bend")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        rc, rows = gate(p)
        moved = "MOVED" if text != live else "unchanged"
        want = {"CONTROL": 0, "PLANT-1": 1, "PLANT-2": 0, "PLANT-3": 0}[name]
        ok = rc == want
        bad += not ok
        print(f"  {name:9} {moved:9} rc={rc} want={want} {'ok' if ok else 'MISMATCH'}")
        for row in rows[:6]:
            print(f"      {os.path.relpath(row, ROOT) if row.startswith('/') else row}")
    print(f"  {len(arms) - bad}/{len(arms)} arms as expected")
    return bad


if __name__ == "__main__":
    sys.exit(main())