#!/usr/bin/env python3
"""Differ for tinybendygrad/runtime/support/memory.bend.

THE HARNESS DIFFS WHOLE `name=value` LINES AND NOTHING ELSE. Comparing ROW
NAMES reports 0 for every mutation, which has happened twice in this project,
so the comparison is on the whole line and the value is part of the key.

It also reports ROWS ONLY IN ONE SIDE. A differ that skips them turns a renamed
row into a silent pass in both directions.

    .agents/slop/memory-diff.py
"""
import subprocess, sys, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BEND = os.path.join(ROOT, 'tinybendygrad/runtime/support/memory.bend')

def run_bend():
    p = subprocess.run(['./bin/bend', BEND], cwd=ROOT, capture_output=True, text=True)
    # the compiled lane and the interpreted lane must AGREE; the native lane is
    # the one the gate reads.
    return p.stdout, p.stderr, p.returncode

def run_oracle():
    p = subprocess.run(['.venv/bin/python', '.agents/slop/memory_oracle.py'],
                       cwd=ROOT, capture_output=True, text=True)
    return p.stdout, p.stderr, p.returncode

def parse(txt):
    out = {}
    for line in txt.split('\n'):
        line = line.rstrip()
        if not line or '=' not in line: continue
        k, v = line.split('=', 1)
        if k in out:
            print(f"DUPLICATE ROW NAME in input: {k}", file=sys.stderr)
        out[k] = v
    return out

bend, berr, brc = run_bend()
orc, oerr, orc_rc = run_oracle()

if brc != 0 or berr.strip():
    print("BEND LANE FAILED", file=sys.stderr)
    print(berr, file=sys.stderr)
    sys.exit(2)
if orc_rc != 0:
    print("ORACLE FAILED", file=sys.stderr)
    print(oerr, file=sys.stderr)
    sys.exit(2)

B = parse(bend)
O = parse(orc)

bad = 0
only_b = sorted(set(B) - set(O))
only_o = sorted(set(O) - set(B))
diff = sorted(k for k in set(B) & set(O) if B[k] != O[k])

for k in only_b:
    print(f"ONLY-IN-BEND {k}={B[k]}")
    bad += 1
for k in only_o:
    print(f"ONLY-IN-ORACLE {k}={O[k]}")
    bad += 1
for k in diff:
    print(f"DISAGREE {k}: bend={B[k]} cpython={O[k]}")
    bad += 1

print(f"\nrows: bend={len(B)} oracle={len(O)} compared={len(set(B) & set(O))} "
      f"disagreements={bad}")
sys.exit(1 if bad else 0)
