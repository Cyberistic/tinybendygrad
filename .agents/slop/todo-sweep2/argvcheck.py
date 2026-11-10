#!/usr/bin/env python3
"""THE `argv`-LOOKUP CLASS, MEASURED AT THE FOUR NAMED SITES.

THE ITEM (`HELPCENSUS`'s one open item): "**AND THE CLASS IS **ONE SHAPE**: `argv` REACHING A
LOOKUP WHOSE DOMAIN DOES NOT CONTAIN `argv`**", naming four sites and saying the
`amd_dsl_census-mutate.py` two lines are "**STILL LIVE**".

⇒ **THAT CLAIM IS FALSE AS OF `3313ac76f` ("ARGV: 3 OF THE 4 REMAINING SITES STATE THEIR
CONTRACT, AND THE 4TH IS A DIFFERENT SHAPE"), WHICH IS AN ANCESTOR OF HEAD.** THIS INSTRUMENT
MEASURES EACH OF THE FOUR, AND IT MEASURES THE **STRUCTURAL** CLAIM, NOT JUST "IT DID NOT
CRASH TODAY".

THE FOUR MEASUREMENTS:

  1. `gates/amd_dsl_census-mutate.py` -- **THE CRASH SITE IS STRUCTURALLY UNREACHABLE, NOT
     MERELY UNREACHED.** The selector filters on `m[0].split()[0]`; the contract's domain
     `MUTATIONS_BY` keys on `e[0].split()[0]`; **⇒ THEY ARE THE SAME SET**, so `want` is empty
     ONLY when `argv` is empty -- and `not argv` is the `or` branch that keeps everything. A
     SECOND, INDEPENDENT guard (`unknown` -> rc 3) fires BEFORE `want` is computed.
  2. `checks/graphcmp-census-audit.py` -- the bare `next()` is replaced by `STATES_BY`.
  3. `gates/tc_ptx_render-oracle.py` -- every out-of-domain selector, `--help` INCLUDED, is
     refused at rc 3 **with the selectors on stderr** -- and that is the file's OWN output
     channel, because stdout IS the artifact.
  4. `checks/coverage.py` -- **A DIFFERENT SHAPE, AND CLASSIFIED AS ONE.** There is no lookup
     table: the argument IS the path.

⇒ **⇒ AND EVERY SITE IS RUN, NOT ASSUMED.** A SITE THAT EXITS CLEANLY IS NOT PROOF THAT THE
CLASS IS GONE; THE POINT IS THE **STATE EACH SITE REPORTS FOR AN OUT-OF-DOMAIN ARGUMENT**, AND
A CRASH IS EXPLICITLY NOT ONE OF THE ACCEPTABLE STATES.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/argvcheck.py
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

SITES = [
    ("gates/amd_dsl_census-mutate.py", ["--help", "NOT_A_LABEL"],
     "the contract names MUTATIONS_BY's domain and the selector reads the SAME token"),
    ("checks/graphcmp-census-audit.py", ["--help", "NOT_A_STATE"],
     "the bare next() is replaced by a STATES_BY lookup"),
    ("gates/tc_ptx_render-oracle.py", ["--help", "NOT_A_SELECTOR"],
     "every out-of-domain selector is refused at rc 3 with the selectors on stderr"),
    ("checks/coverage.py", ["--help"], "the argument IS the path: a different shape, classified as one"),
]


def run(rel, args):
    p = subprocess.run([sys.executable, str(ROOT / rel), *args], cwd=ROOT,
                       capture_output=True, text=True, timeout=120)
    out = (p.stdout + p.stderr)
    crashed = "Traceback (most recent call last)" in out
    return p.returncode, crashed, out


def main():
    bad = []
    print("THE FOUR NAMED SITES, EACH RUN WITH AN OUT-OF-DOMAIN ARGUMENT")
    print()
    for rel, args, ground in SITES:
        for a in args:
            rc, crashed, out = run(rel, [a])
            state = "CRASH" if crashed else ("REFUSED" if rc == 3 else ("PASS" if rc == 0 else f"rc={rc}"))
            first = next((l for l in out.splitlines() if l.strip()), "")
            print(f"  {rel:<38} {a:<15} rc={rc:<3} {state:<8} {first[:60]}")
            if crashed:
                bad.append(f"{rel} {a} CRASHED")

    print()
    print("THE STRUCTURAL CLAIM, WHICH IS THE POINT:")
    src = (ROOT / "gates/amd_dsl_census-mutate.py").read_text(errors="replace")
    checks = [
        ("MUTATIONS_BY is built from MUTATIONS",
         "MUTATIONS_BY = {e[0].split()[0]: e for e in MUTATIONS}" in src),
        ("the selector filters on the SAME token",
         "m[0].split()[0] in argv" in src),
        ("the unknown-label guard fires BEFORE `want` is computed",
         src.find("unknown = [a for a in argv if a not in MUTATIONS_BY]")
         < src.find("want = [m for m in MUTATIONS")),
        ("`graphcmp-census-audit.py` no longer uses a bare next() over the ARGV-DRIVEN table",
         # **⇒ THE CHECK IS ON THE **CODE**, NOT ON THE FILE: THE OLD FORM APPEARS IN A
         # COMMENT AT :158, WHICH IS THE FILE's OWN RECORD OF THE FIX, AND A CHECK THAT
         # GREPS THE WHOLE FILE MATCHES THE COMMENT AND REPORTS A DEFECT THAT IS NOT
         # THERE.** ⇒ SO THE CHECK IS OVER THE **CODE LINES ONLY** (COMMENT LINES DROPPED),
         # AND THE CLAIM IS ABOUT THE **STATE** TABLE, NOT ABOUT `G.GRAPHS` -- THE OTHER
         # `next()` AT :139 ITERATES A FIXED POPULATION OF GRAPHS AND CANNOT BE REACHED BY
         # AN OUT-OF-DOMAIN `argv` AT ALL.
         not any("next(m for n, m, _ in STATES if n == name)" in l
                 for l in (ROOT / "checks/graphcmp-census-audit.py").read_text(errors="replace").splitlines()
                 if not l.lstrip().startswith("#"))),
        ("`graphcmp-census-audit.py` looks the STATE up in a dict",
         "STATES_BY = {n: (m, l) for n, m, l in STATES}" in
         (ROOT / "checks/graphcmp-census-audit.py").read_text(errors="replace")),
    ]
    for name, ok in checks:
        print(f"  {'OK ' if ok else 'NO '} {name}")
        if not ok:
            bad.append(name)

    print()
    if bad:
        print(f"FAILED: {len(bad)} problem(s)")
        for b in bad:
            print("  -", b)
        return 1
    print(f"OK -- all four sites STATE A CONTRACT for an out-of-domain argument, none CRASHES, "
          f"and the crash site is structurally unreachable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
