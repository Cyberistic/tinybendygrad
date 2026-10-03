#!/usr/bin/env python3
"""Capture a row baseline for a .bend file, with the traps the brief names, handled.

  * `--check-only` exits 1 even on a clean file: READ THE FIRST LINE, never the status.
  * the machine stack overflows on ~1 run in 20, sometimes printing ZERO rows, and a
    0-row result is indistinguishable from "not started": RETRY on 0 rows.
  * a file with no `main` prints 0 rows forever: say so rather than reporting 0.
  * a rename must move ZERO rows, so the baseline is `name=value` LINES, not row names.

    python3 .agents/slop/names-ag-baseline.py <file.bend> [out.txt]
"""
import subprocess, sys, os, time

BEND = './bin/bend'

def run(path, tries=8):
    for i in range(tries):
        p = subprocess.run([BEND, path], capture_output=True, text=True, timeout=1800)
        out = (p.stdout or '') + (p.stderr or '')
        rows = [l for l in out.split('\n') if '=' in l and not l.startswith('-')]
        over = 'machine stack overflowed' in out
        if over:
            print('  attempt %d: STACK OVERFLOW, retrying' % (i + 1), file=sys.stderr)
            time.sleep(2); continue
        if not rows and i < tries - 1:
            print('  attempt %d: ZERO ROWS, retrying' % (i + 1), file=sys.stderr)
            time.sleep(2); continue
        return out, rows, over
    return out, rows, True

def main():
    path = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else None
    src = open(path).read()
    if '\ndef main(' not in src and not src.startswith('def main('):
        print('NO main in %s -- it prints 0 rows forever; not a baseline' % path)
        return 1
    out, rows, over = run(path)
    first = out.strip().split('\n')[0] if out.strip() else '(no output)'
    print('%s  rows=%d  first-line=%s' % (path, len(rows), first))
    if dst:
        with open(dst, 'w') as f: f.write('\n'.join(sorted(r.strip() for r in rows)) + '\n')
        print('  wrote %s' % dst)
    return 0

main()