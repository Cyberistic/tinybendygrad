#!/usr/bin/env python3
"""ARGOWNER falsification: does the COMPILER agree with census.py's closed set?

census.py claims that of the 189 `Arg` matches in tinybendygrad/, exactly 3 are
CLOSED (a 22nd constructor would break them).  A regex cannot settle that.  So:

  PASS 1  baseline -- compile every file that census.py found a site in, untouched
  PASS 2  probe    -- the SAME files, with ONE line added to `type Arg is Data:`:
                      `ABoolList{bs: List<&2, Bool>}`
  DELTA            -- files whose error set GREW, and grew by an
                      `expected : cases for ops.ABoolList` line.

The DELTA is the ground truth.  census.py's closed set is correct iff
DELTA-files == closed-set-files.  If it disagrees, the census is wrong and the
COMPILER is right.

Every run is under `checks/bounded.py --mb 2048` and the VERDICT TOKEN is
recorded (`WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`), never the exit
code: AGENTS.md records a unit that lost 425 rows by believing the status.

SEQUENTIAL by construction.  The 36 site files' largest MEASURED peak is 745 MB
(.agents/slop/peakrss/census.rows, read for this run), so the concurrent sum is
that one number, well under 60% of hw.memsize=16384 MB.
"""
import hashlib
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
OPS = os.path.join(ROOT, "tinybendygrad", "uop", "ops.bend")
SITES = os.path.join(ROOT, ".agents/slop/argowner/sitefiles.rows")
CLOSED = os.path.join(ROOT, ".agents/slop/argowner/census.rows")
ANCHOR = "  ATuple{ys: List<&2, U32>}\n"
PROBE = "  ABoolList{bs: List<&2, Bool>}\n"


def md5(p):
    with open(p, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def run(target):
    """-> (token, sorted set of error lines).  The TOKEN is the verdict."""
    r = subprocess.run(
        [os.path.join(ROOT, ".venv/bin/python"), "checks/bounded.py",
         "--seconds", "600", "--mb", "2048", "--",
         "./bin/bend", target, "--check-only"],
        cwd=ROOT, capture_output=True, text=True)
    tok = "NO-TOKEN"
    for ln in r.stderr.split("\n"):
        if ln.startswith("[bounded] "):
            m = re.search(r"\b(WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)\b", ln)
            tok = m.group(1) if m else "UNPARSED-TOKEN"
    errs = {ln.strip() for ln in r.stderr.split("\n")
            if ln.strip() and not ln.startswith("[bounded] ") and ln.strip() != "Error:"}
    return tok, errs


def main():
    targets = [t for t in open(SITES).read().split() if t.endswith(".bend")]
    targets.sort()
    closed = set()
    for ln in open(CLOSED):
        if " EXHAUSTIVE " in ln or " INCOMPLETE " in ln:
            closed.add(ln.split()[0])
    print(f"# ARGOWNER falsification -- target {len(targets)} site files (census.py), "
          f"closed set {len(closed)}")
    print(f"# ops.bend md5 BEFORE {md5(OPS)}")
    base = {}
    print("\n## PASS 1  BASELINE (untouched tree)")
    for t in targets:
        tok, errs = run(t)
        base[t] = errs
        print(f"  {t:52s} token={tok} error-lines={len(errs)}")

    src = open(OPS).read()
    if src.count(ANCHOR) != 1:
        print(f"REFUSED: anchor {ANCHOR.strip()!r} occurs {src.count(ANCHOR)}x in ops.bend")
        return 3
    open(OPS, "w").write(src.replace(ANCHOR, PROBE + ANCHOR))
    print(f"\n## PASS 2  PROBE (+1 line `ABoolList` in `type Arg is Data:`)")
    print(f"# ops.bend md5 PROBE  {md5(OPS)}")
    grew, probe_tag = [], []
    for t in targets:
        tok, errs = run(t)
        new = errs - base[t]
        gone = base[t] - errs
        if new:
            grew.append(t)
            probe_tag += [e for e in new if "ABoolList" in e]
        print(f"  {t:52s} token={tok} error-lines={len(errs)} NEW={len(new)} GONE={len(gone)}"
              + ("   <-- BREAKS ON A NEW CTOR" if new else ""))
        for e in sorted(new):
            print(f"      + {e}")
        for e in sorted(gone):
            print(f"      - {e}")

    open(OPS, "w").write(src)  # REVERT, always, including on the REFUSED path below
    print(f"\n## REVERT\n# ops.bend md5 AFTER  {md5(OPS)}  restored={md5(OPS) == base_md5}")


if __name__ == "__main__":
    base_md5 = md5(OPS)
    sys.exit(main())