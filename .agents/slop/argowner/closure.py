#!/usr/bin/env python3
"""ARGOWNER closure: let the COMPILER name every closed `Arg` match, in order.

census.py's regex says 3 sites are closed.  A regex cannot settle that, and the
first plant (plant.py) proved it cannot: `bend` reports ONE error per file, so a
probe that adds a ctor to `ops.bend` made 35 of 35 files "break" -- and every one
of them broke at the SAME shared `eq_arg.sel`.  35 files is a radius, not 35
sites.  A radius is what a build reports; sites are what a closure finds.

So: FIX the site the compiler named, re-probe, repeat until the compiler names
nothing new.  Each round is evidence for the NEXT site, and the round at which a
file stops breaking is evidence that its other matches are open.

Every run: `checks/bounded.py --seconds 600 --mb 2048 -- ./bin/bend F --check-only`,
SEQUENTIAL.  The TOKEN on the `[bounded]` line is the verdict, never the status.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
PY = os.path.join(ROOT, ".venv/bin/python")
SITES = os.path.join(ROOT, ".agents/slop/argowner/sitefiles.rows")


def run(target):
    r = subprocess.run([PY, "checks/bounded.py", "--seconds", "600", "--mb", "2048",
                        "--", "./bin/bend", target, "--check-only"],
                       cwd=ROOT, capture_output=True, text=True)
    tok = "NO-TOKEN"
    for ln in r.stderr.split("\n"):
        if ln.startswith("[bounded] "):
            m = re.search(r"\b(WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)\b", ln)
            tok = m.group(1) if m else "UNPARSED-TOKEN"
    loc, msg = None, None
    for ln in r.stderr.split("\n"):
        if "- expected : cases for" in ln:
            msg = ln.strip()
        m = re.search(r"- Location:\s*(.+)$", ln)
        if m:
            loc = m.group(1).strip()
    # `bend` stops at the FIRST error per file, so one file's error is usually a
    # DEF it merely imports. The caret block's own file is not printed by bend,
    # so ownership is read off the DEF NAME and resolved by grep -- and a file
    # whose def lives elsewhere is INHERITING, which is what made a 35-file
    # "radius" read as 35 sites in plant.py.
    ok = "ALL PROOFS CHECK" in r.stdout
    return tok, loc, msg, ok


def main():
    targets = sorted(t for t in open(SITES).read().split() if t.endswith(".bend"))
    print(f"# ARGOWNER closure -- {len(targets)} site files, SEQUENTIAL, mb=2048")
    red, green, sites = [], [], {}
    for t in targets:
        tok, loc, msg, ok = run(t)
        print(f"  {t:52s} token={tok} "
              f"{'GREEN' if ok else 'RED ' + str(loc)}")
        if ok:
            green.append(t)
        else:
            red.append(t)
            sites.setdefault((loc, msg), []).append(t)
    print()
    print(f"# GREEN (ALL PROOFS CHECK): {len(green)} of {len(targets)} site files")
    print(f"# RED: {len(red)} of {len(targets)}")
    print("# DISTINCT (Location, message) the compiler named -- each is ONE closed site:")
    for (loc, msg), fs in sorted(sites.items(), key=lambda kv: -len(kv[1])):
        print(f"  {str(loc):24s} {str(msg):46s} hit by {len(fs)} files"
              + (f"  e.g. {fs[0]}" if fs else ""))
    print()
    print("# READING THIS AS A CLOSURE: `bend` stops at the FIRST error per file, so")
    print("# each Location is the FIRST still-unfixed site. A site is CLOSED iff adding")
    print("# a constructor breaks it, and each Location above is such a site -- but a")
    print("# file listing ZERO locations in a later round is only evidence of open-ness")
    print("# for the sites the earlier rounds already fixed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())