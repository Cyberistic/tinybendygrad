#!/usr/bin/env python3
"""HOW MANY MORE FIXTURES LIKE STAGE 3's AND STAGE 5's ARE THERE, AND WHY DID NOTHING COUNT THEM.

`checks/repro-paths.py` is the instrument for the class "a gate's own required input was deletable
while the gate still named it". It counts a path-shaped token under `.agents/slop/`, `checks/` or
`gates/` with a `.sh`/`.py`/`.bend` suffix. Its own `REF` regex, quoted:

    REF = re.compile(r"(?:^|\\s)((?:\\.agents/slop/|checks/|gates/)[\\w./-]+\\.(?:sh|py|bend))")

**`.mjs` AND `.txt` ARE NOT IN THAT ALTERNATION.** So the two fixtures this unit was sent to
restore are both INVISIBLE to the instrument: `xd2/{cdp,serve,sh}.mjs` and
`ops_bend-milestone-expected.txt`. Every one of them could be deleted, and `repro-paths.py` would
print the same 56 whether they were there or not -- which is exactly why the class survived a
citation-set fix that a reader would reasonably call sufficient.

This is the census: every path `checks/e2e.py` names as a stage input, split into the ones the
instrument counts and the ones it is structurally blind to.

    .venv/bin/python .agents/slop/fixures/blind-spot.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
# `checks/e2e.py` NAMES ITS INPUTS IN CODE, not in prose: every stage's command line is a literal
# argv. So the census reads the CODE POSITIONS, which is where the obligation lives and where a
# docstring's citation would not.
STAGE_INPUTS = [
    ("1", ".agents/slop/e2e_mm.py"),
    ("2", ".agents/slop/e2e_mm.bend"),
    ("3", ".agents/slop/e2e_mm_run.mjs"),
    ("3", "xd2/cdp.mjs (imported by stage 3)"),
    ("3", "xd2/serve.mjs (imported by stage 3)"),
    ("3", "xd2/sh.mjs (imported by stage 3)"),
    ("3", "tinybendygrad/runtime/webgpu_call.js (copied by stage 3)"),
    ("4", ".agents/slop/e2e_mm_gate.py"),
    ("5", ".agents/slop/opsbend-milestone.sh"),
    ("5", ".agents/slop/opsbend_milestone_gate.py"),
    ("5", ".agents/slop/ops_bend-milestone-expected.txt"),
    ("5", "tinybendygrad/runtime/ops_python.bend"),
    ("5", "tinybendygrad/runtime/ops_bend.bend"),
    ("6", ".agents/slop/e2e_port/run-port-mm.sh"),
    ("7", ".agents/slop/f64/run-f64.sh"),
]


def main() -> int:
    spec = importlib.util.spec_from_file_location("rp", ROOT / "checks/repro-paths.py")
    rp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rp)

    seen_blind: dict[str, str] = {}
    counted = 0
    for stage, tok in STAGE_INPUTS:
        name = tok.split(" ")[0]
        full = name if name.startswith(("checks/", "gates/", ".agents/")) \
            else f".agents/slop/{name}"
        if not full.startswith(".agents/slop"):
            full = name  # tinybendygrad/... is outside the instrument's roots entirely
        if rp.REF.search(full):
            counted += 1
        else:
            seen_blind.setdefault(stage, []).append(tok)

    total = counted + sum(len(v) for v in seen_blind.values())
    print(f"stage inputs checks/e2e.py names: {total}")
    print(f"  repro-paths.py COUNTS them:  {counted}")
    print(f"  repro-paths.py CANNOT SEE:    {total - counted}  "
          f"(`REF`'s suffix class is sh|py|bend, so .mjs, .txt and .js are outside it)")
    for stage in sorted(seen_blind):
        print(f"    stage {stage}: " + ", ".join(seen_blind[stage]))
    print("\nA SWEEP CAN DELETE EVERY PATH IN THE THIRD GROUP AND repro-paths.py PRINTS THE SAME "
          "NUMBER.\nThat is the answer to 'why does the instrument run at all if it cannot prevent "
          "them':\nit counts what it can see, and the two fixtures this unit restored are both "
          "outside\nwhat it can see, so restoring them moved its output by ZERO.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())