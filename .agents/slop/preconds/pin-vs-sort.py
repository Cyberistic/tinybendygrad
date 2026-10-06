#!/usr/bin/env python3
"""A PIN IS A SEED; A SORT IS A LAW. This measures which one `graphcmp-oracle.py:119` needs.

The brief is right that both are wanted and not redundant, and this is the measurement that
separates them:

  * A PIN (`PYTHONHASHSEED=0`) makes the output deterministic ON ONE INTERPRETER. It says:
    "run it under seed 0". It does not say the ORDER is correct, and a future CPython whose
    set layout differs reorders the line under the same seed. MEASURED below: 5 seeds, one
    order each -- so a pin fixes the line at the cost of a fact nobody can check.
  * A SORT (`sorted(...)`) makes the output correct under EVERY seed and every interpreter.
    MEASURED below: the sorted rendering is byte-identical across all 5 seeds.

No `bend`, no `graphcmp`, no tinygrad: the set in question is `{REDUCE, RANGE, ALLREDUCE,
MUL, PERMUTE, COPY}`, which `.agents/slop/graphcmp-oracle.py:119` prints as `py['ops'] ^
bd['ops']`, and what is under test is the ORDER, not the membership.
"""
from __future__ import annotations

import subprocess
import sys

MEMBERS = ["REDUCE", "RANGE", "ALLREDUCE", "MUL", "PERMUTE", "COPY"]
# The insertion order `census()` builds: py's row order first, then bend-only ops. Reused
# verbatim from `.agents/slop/preconds/seed-recovery.py`'s reconstruction of `allred`.
INSERTION = ["ALLREDUCE", "COPY", "RANGE", "MUL", "PERMUTE", "REDUCE"]

UNSORTED = ("import sys\n"
            "s = set()\n"
            "for m in sys.argv[1:]:\n"
            "    if m in s:\n"
            "        s.remove(m)\n"
            "    else:\n"
            "        s.add(m)\n"
            "print(s)")
SORTED = UNSORTED + "\nprint(sorted(s))"

SEEDS = ["0", "1", "2", "17", "329"]


def run(prog: str, seed: str) -> str:
    r = subprocess.run([sys.executable, "-c", prog, *INSERTION], capture_output=True, text=True,
                       env={"PYTHONHASHSEED": seed, "PATH": "/usr/bin:/bin"})
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def main() -> int:
    print(f"members ({len(MEMBERS)}): {MEMBERS}\ninsertion order      : {INSERTION}\n")
    print(f"{'seed':<7}{'AS PRINTED TODAY (set)':<50}{'AS SORTED'}")
    raw, srt = set(), set()
    for s in SEEDS:
        a, b = run(UNSORTED, s), run(SORTED, s).splitlines()[-1]
        raw.add(a)
        srt.add(b)
        print(f"{s:<7}{a:<50}{b}")
    print(f"\ndistinct `set(...)` renderings over {len(SEEDS)} seeds : {len(raw)}")
    print(f"distinct sorted renderings over {len(SEEDS)} seeds    : {len(srt)}")
    print("\nVERDICT")
    print(f"  a PIN alone does NOT fix the line: {len(raw)} distinct renderings over "
          f"{len(SEEDS)} seeds.")
    print("  Pinning to seed 0 would fix it only by ACCIDENT of how THIS interpreter lays")
    print("  THIS set out, and nothing in the tree would say so or notice it change.")
    print(f"  a SORT alone DOES fix the line: {len(srt)} distinct rendering over "
          f"{len(SEEDS)} seeds -- byte-identical")
    print("  under every seed tried, so it is a property of the OUTPUT, not of the machine.")
    print("\nBOTH ARE ADDED, and they are not redundant:")
    print("  the SORT makes the line correct; the PIN stops any OTHER set print in the corpus")
    print("  from differing between two runs of the same tree. Fixing one does not fix the")
    print("  other: with the sort in place and no pin, THIS line is stable and the NEXT")
    print("  unsorted set print is not; with the pin and no sort, this line is stable only")
    print("  under one interpreter.")
    return 0 if len(raw) > 1 and len(srt) == 1 else 1


if __name__ == "__main__":
    sys.exit(main())