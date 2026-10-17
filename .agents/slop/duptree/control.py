#!/usr/bin/env python
"""CONTROL for dupscan.py. A rate is REFUSED unless both lanes behave.

POSITIVE lane: the detector MUST fire on 591f6b499 (the reported finding).
NEGATIVE lane: the detector MUST stay silent on commits that push fine,
  which are proven good by a fact rather than by assumption -- they are on
  origin/master, and origin accepted them. `git merge-base --is-ancestor`
  is the oracle; the population is DISCOVERED from `git rev-list`, never
  listed by hand.

Exit 0 = control PASS, the rate may be reported.
Exit 1 = control FAIL, the rate is REFUSED.
"""

import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dupscan import Batch, git, scan  # noqa: E402

GOOD = "591f6b4993364806eec638d1e69dce547028c132"


def on_origin(c):
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", c, "origin/master"],
        capture_output=True,
        env={k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"},
    ).returncode == 0


def main():
    n_neg = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    # NEGATIVE population: the newest n commits on origin/master, minus GOOD.
    neg = [c for c in git(["rev-list", "--max-count=%d" % n_neg, "origin/master"]).decode().split()
           if c != GOOD and on_origin(c)]
    b = Batch()
    try:
        pos_rows = scan([GOOD], b)
        neg_rows = scan(neg, b)
    finally:
        b.close()

    print("# POSITIVE\t591f6b499\trows=%d" % len(pos_rows))
    for r in pos_rows:
        print("#   \t" + "\t".join(str(x) for x in r))
    print("# NEGATIVE\tn=%d (all verified on origin/master)\trows=%d" % (len(neg), len(neg_rows)))
    for r in neg_rows:
        print("#   \t" + "\t".join(str(x) for x in r))

    ok = bool(pos_rows) and not neg_rows and len(neg) > 0
    print("# CONTROL\t%s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())