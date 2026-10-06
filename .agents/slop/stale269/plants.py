#!/usr/bin/env python3
"""THE TWO PLANTS, AND NEITHER TOUCHES THE TREE.

    .venv/bin/python .agents/slop/stale269/plants.py

**A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES**, so each arm asserts that its own anchor text
is in the file BEFORE it runs the gate, and exits non-zero if the tree moved underneath it. The
verdict is then about the harness and not about the plant.

| arm | what it plants | must show |
|---|---|---|
| `CONTROL`     | nothing, the live bytes | the census's own counts, so a RED below is the plant |
| `PLANT-A`     | a restore whose line does NOT carry the claim (`pm_bufferize` -> the class-attribute DECLARATION) | the census reports `HOLDS` -- **the class a substring pin cannot see** |
| `PLANT-B`     | a claim naming FOUR lines where the gate binds its quote to the first | `(reduce.py:44/:71)` -> `(reduce.py:71/:71)` -- **the list-collapse a restore causes** |

PLANT-A IS THE `Allocator` CLASS AND IT IS THE ONE THAT MATTERS. `pm_bufferize` occurs EXACTLY ONCE
in `tinygrad/device.py`, on `pm_bufferize:Any = None` -- and `device.bend`'s claim is about the
`PatternMatcher([` RULE TABLE that upstream moved to `tinygrad/runtime/support/hcq2.py:547` in
`4c5ec4602`. Every pin available to the census says the citation holds: the file resolves, the line
is inside the range, the substring is present. **The claim is about a DIFFERENT LINE and the
evidence is invariant under the edit that moved it**, which is the same blindness as `PLANT-2` in
`.agents/slop/speccite/README.md` §3, one class up.

PLANT-B IS THE FAILURE MY OWN WRITER HAD, PLANTED. It is here because "an assertion that has never
failed has not been tested", and this is the assertion that caught it: `write.py` refuses a claim
line that names more than one citation.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/stale269")
OUT = os.path.join(HERE, "plants")
GATE = os.path.join(ROOT, "checks/citation-gate.py")

# PLANT-A: the real `device.bend` claim, retargeted onto the class-attribute DECLARATION. The
# substring is present, the line is in range, and the claim is about a rule table 157 lines away.
PLANT_A = ("# `pm_bufferize` -- device.py:390-390. THE RULE TABLE.\n"
           "#\n"
           "#   PatternMatcher([\n")
# PLANT-B: a two-line claim where the gate's longest span belongs to the SECOND number.
PLANT_B = "# --- 17-18: THE `dtype is not None` ARMS (reduce.py:71/:71). These are the defs\n"
PLANT_B_ORIG = "# --- 17-18: THE `dtype is not None` ARMS (reduce.py:44/:71). These are the defs\n"


def census(path: str) -> tuple[int, list[str]]:
    r = subprocess.run([sys.executable, GATE, path], cwd=ROOT, capture_output=True, text=True)
    return r.returncode, [l.strip() for l in r.stdout.splitlines() if ".bend:" in l]


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    live = open(os.path.join(ROOT, "tinybendygrad/device.bend"), encoding="utf-8").read()
    arms = {"CONTROL": live,
            "PLANT-A": live.replace("# `pm_bufferize` -- device.py:390-405. THE RULE TABLE.\n", PLANT_A),
            "PLANT-B": open(os.path.join(ROOT, "tinybendygrad/mixin/reduce.bend"), encoding="utf-8").read()
                          .replace(PLANT_B_ORIG, PLANT_B)}
    srcs = {"CONTROL": ("tinybendygrad/device.bend", live),
            "PLANT-A": ("tinybendygrad/device.bend", live),
            "PLANT-B": ("tinybendygrad/mixin/reduce.bend",
                        open(os.path.join(ROOT, "tinybendygrad/mixin/reduce.bend"), encoding="utf-8").read())}
    bad = 0
    for name, text in arms.items():
        src, orig = srcs[name]
        moved = text != orig
        if name != "CONTROL" and not moved:
            print(f"  {name} DID NOT MOVE: its anchor is not in {src}, so this arm proves NOTHING")
            return 2
        p = os.path.join(OUT, "device.bend" if name != "PLANT-B" else "reduce.bend")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        rc, rows = census(p)
        # WHAT IT MUST SHOW, PER ARM.
        if name == "PLANT-A":
            hit = [r for r in rows if "device.bend" in r and "pm_bufferize" in r]
            ok = bool(hit) and "HOLDS" not in hit[0]
            print(f"  PLANT-A  {'MOVED' if moved else 'UNCHANGED'}  rc={rc}  "
                  f"{'the census calls it HOLDS -- it cannot see this class' if not hit or ok else 'unexpected'}")
            for r in hit[:3]:
                print(f"      {r[:150]}")
        elif name == "PLANT-B":
            line = next(l for l in text.splitlines()
                       if l.startswith("# --- 17-18: THE `dtype is not None` ARMS"))
            collapsed = "71/:71" in line
            ok = collapsed
            print(f"  PLANT-B  {'MOVED' if moved else 'UNCHANGED'}  rc={rc}  "
                  f"{'THE LIST COLLAPSES TO 71/:71 and now reads as checked' if ok else 'DID NOT COLLAPSE'}")
            print(f"      {line.strip()[:140]}")
        else:
            print(f"  CONTROL  rc={rc}  {len(rows)} adjudicable rows in the live bytes")
        bad += not ok if name != "CONTROL" else 0
    shutil.rmtree(OUT, ignore_errors=True)
    print(f"  {3 - bad}/3 arms as expected; the tree was never modified")
    return bad


if __name__ == "__main__":
    sys.exit(main())