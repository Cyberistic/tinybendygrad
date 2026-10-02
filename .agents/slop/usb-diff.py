#!/usr/bin/env python3
"""Differ for tinybendygrad/runtime/support/usb.bend.

DIFFS WHOLE `name=value` LINES, NOT ROW NAMES. agent-core.md records a
name-comparing harness that reported 0 for all 30 mutations in one unit and 0
for all 68 in another.

Usage:  usb-diff.py <bend-output.txt> [--oracle oracle.txt]
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
ORACLES = ["usb-oracle.py", "usb-oracle-arith.py"]
BEND = HERE.parent.parent / "tinybendygrad/runtime/support/usb.bend"


def bend_out() -> dict:
    r = subprocess.run([str(HERE.parent.parent / "bin/bend"), str(BEND)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("BEND FAILED", r.returncode)
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit(2)
    d = {}
    for line in r.stdout.split("\n"):
        line = line.rstrip()
        if "=" not in line or line.startswith("usb-done"):
            continue
        nm, _, v = line.partition("=")
        d[nm.strip()] = v
    return d


def oracle_out() -> dict:
    r = subprocess.run([sys.executable, str(HERE / "usb-oracle-run.py")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("ORACLE FAILED")
        print(r.stderr[-3000:])
        sys.exit(2)
    d = {}
    for line in r.stdout.split("\n"):
        line = line.rstrip()
        if "=" not in line or line.startswith("usb-done"):
            continue
        nm, _, v = line.partition("=")
        d[nm.strip()] = v
    return d


def main():
    got = bend_out()
    want = oracle_out()
    missing = sorted(set(want) - set(got))
    extra = sorted(set(got) - set(want))
    bad = sorted(nm for nm in set(want) & set(got) if want[nm] != got[nm])
    for nm in bad:
        print(f"DISAGREE {nm}\n  bend={got[nm]}\n  cpy ={want[nm]}")
    for nm in missing:
        print(f"ORACLE-ONLY {nm}={want[nm]}")
    for nm in extra:
        print(f"BEND-ONLY   {nm}={got[nm]}")
    print(f"rows bend={len(got)} oracle={len(want)} disagree={len(bad)} "
          f"oracle_only={len(missing)} bend_only={len(extra)}")
    sys.exit(1 if (bad or missing or extra) else 0)


main()