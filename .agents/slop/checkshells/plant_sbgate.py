#!/usr/bin/env python3
"""Two states for checks/sb-gate.sh, distinguishable, no bend compiled.

STATE B (fixture present):  BASE=oracles/schedule-bodies/BEFORE-rows.rows resolves, so the
                            gate refuses on the NEXT input, the CPython oracle.
STATE A (fixture moved):    the same gate refuses on the BASE itself.

Restoration is proven by sha256 in a finally block. Nothing is committed.
"""
import hashlib
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
RUNS = os.path.join(ROOT, ".agents/slop/checkshells/runs")
FIX = os.path.join(ROOT, "oracles/schedule-bodies/BEFORE-rows.rows")
BAK = FIX + ".sbgate-plant-bak"


def run(tag):
    p = subprocess.run(["sh", "checks/sb-gate.sh"], cwd=ROOT, capture_output=True, text=True)
    open(os.path.join(RUNS, tag + ".out"), "w").write(p.stdout)
    open(os.path.join(RUNS, tag + ".err"), "w").write(p.stderr)
    return p.returncode, p.stdout.strip()


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]


def main():
    before = sha(FIX)
    try:
        rc, out = run("sbgate-fix-present")
        print("STATE B  fixture present   rc=%d  %s" % (rc, out))
        shutil.move(FIX, BAK)
        try:
            rc, out = run("sbgate-fix-absent")
            print("STATE A  fixture moved     rc=%d  %s" % (rc, out))
        finally:
            shutil.move(BAK, FIX)
    finally:
        # a concurrent sweep may rename .txt->.rows; only restore if the backup is stranded
        if os.path.exists(BAK) and not os.path.exists(FIX):
            shutil.move(BAK, FIX)
    after = sha(FIX)
    print("RESTORED  sha256 %s -> %s  %s" % (before, after, "OK" if before == after else "MISMATCH"))
    return 0 if before == after else 1


if __name__ == "__main__":
    sys.exit(main())
