#!/usr/bin/env python3
"""PLANT: two states for the anchored rule, then clean up.

State A -- a file under a NESTED runs/ is NO LONGER ignored (was, under `runs/`).
State B -- a file under ROOT runs/ is STILL ignored (that is what `/runs/` is for).

Uses real on-disk probes and deletes them again; never touches anything else.
"""
import os
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True, check=True).stdout.strip()

PROBES = {
    "A": os.path.join(".agents", "slop", "gitignore", "plant", "nested",
                      "runs", "plant-evidence.rows"),
    "B": os.path.join("runs", "plant-probe", "plant-output.rows"),
}


def sh(args):
    p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def main():
    for p in PROBES.values():
        full = os.path.join(ROOT, p)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as fh:
            fh.write("planted probe; safe to delete\n")
    try:
        for state, p in PROBES.items():
            rc, out = sh(["git", "check-ignore", "-v", "--no-index", p])
            verdict = "IGNORED" if rc == 0 else "NOT-IGNORED"
            print(f"state={state} path={p}")
            print(f"state={state} check-ignore={verdict} rule={out or '(none)'}")
        # a REAL capture under a NESTED runs/ -- a `.out`, which is what the `.txt`
        # retirement renamed it to (plancarve 5ed3ad771). It was named as a `.txt` until
        # then, and this line kept pointing at the old name: a probe path that dangles is
        # a demonstration of a file that is no longer there.
        real = ".agents/slop/e2epy/fixtures/repro-green/runs/e2e/e2e-f64.out"
        rc, out = sh(["git", "check-ignore", "-v", "--no-index", real])
        print(f"state=REAL path={real} check-ignore="
              f"{'IGNORED' if rc == 0 else 'NOT-IGNORED'} rule={out or '(none)'}")
    finally:
        for p in PROBES.values():
            try:
                os.remove(os.path.join(ROOT, p))
            except FileNotFoundError:
                pass
        # remove now-empty dirs
        for p in PROBES.values():
            d = os.path.dirname(os.path.join(ROOT, p))
            while d != ROOT:
                try:
                    os.rmdir(d)
                except OSError:
                    break
                d = os.path.dirname(d)


if __name__ == "__main__":
    main()
