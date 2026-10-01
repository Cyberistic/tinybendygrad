#!/usr/bin/env python3
"""mut-rev.py -- the revert entry for fold.bend's srcs.go reversal fix.

One textual edit at a time, in a SANDBOX copy of `tinybendygrad/` (movement.bend and
tensor.bend IMPORT fold.bend, so a run that edits the working file measures a moving
target and corrupts a neighbour's tree). The edit is the REVERT of the fix: restore the
spurious `List.reverse` at the end of `srcs.go`'s accumulator, which is the pre-fix
state. The rows that move are the rows the fix is load-bearing for.

    python3 .agents/slop/mut-rev.py
"""
import os
import shutil
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SANDBOX = tempfile.mkdtemp(prefix='mut-rev-')
SRC = os.path.join(SANDBOX, 'tinybendygrad')

FIXED = '''def srcs.go(ss: List<&2, Derived>, n: Nat, acc: List<&2, Derived>) -> Srcs:
  match ss:
    case Nil{}: Srcs{acc, n}
    case d <> t: srcs.go(t, 1n+n, List.append(&2, Derived, acc, [d]))'''

REVERTED = '''def srcs.go(ss: List<&2, Derived>, n: Nat, acc: List<&2, Derived>) -> Srcs:
  match ss:
    case Nil{}: Srcs{List.reverse(&2, Derived, acc), n}
    case d <> t: srcs.go(t, 1n+n, List.append(&2, Derived, acc, [d]))'''


def stage():
  shutil.copytree(os.path.join(ROOT, 'tinybendygrad'), SRC,
                  ignore=shutil.ignore_patterns('__pycache__'))


def bend(rel, *args):
  r = subprocess.run([os.path.join(ROOT, 'bin', 'bend'), os.path.join(SRC, rel), *args],
                     capture_output=True, text=True, cwd=ROOT)
  return r.returncode, r.stdout + r.stderr


def gate():
  code, out = bend('uop/fold.bend')
  rows = {}
  for line in out.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      rows[k.strip()] = v.strip()
  return code, rows


def edit(path, old, new):
  p = os.path.join(SRC, path)
  s = open(p).read()
  assert s.count(old) == 1, f'{path}: anchor found {s.count(old)} times'
  open(p, 'w').write(s.replace(old, new))


def check(rel):
  code, out = bend(rel, '--check-only')
  return 'ALL PROOFS CHECK' in out


def main():
  stage()
  base_code, base = gate()
  assert base_code == 0 and len(base) == 11, f'unclean baseline: {base}'
  print(f'baseline fold.bend: {len(base)} rows, check={check("uop/fold.bend")}')
  for k in sorted(base):
    print(f'  {k}={base[k]}')

  # THE REVERT. One edit: `Srcs{acc, n}` back to `Srcs{List.reverse(&2, Derived, acc), n}`.
  edit('uop/fold.bend', FIXED, REVERTED)
  code, mut = gate()
  print('\n--- M1  srcs.go: restore the spurious `List.reverse` at the accumulator')
  print(f'    check={check("uop/fold.bend")}')
  moved = [k for k in base if base[k] != mut.get(k)]
  for k in sorted(base):
    mark = 'MOVED' if k in moved else '     '
    print(f'  {mark} {k}: {base[k]} -> {mut.get(k)}')
  print(f'  rows moved: {len(moved)} {sorted(moved)}')

  # The downstream gates that IMPORT fold.bend, over the same reverted tree.
  edit('uop/fold.bend', REVERTED, FIXED)
  for rel in ('tensor.bend', 'uop/movement.bend'):
    code, out = bend(rel)
    rows = {k.strip(): v.strip() for k, _, v in
            (l.partition('=') for l in out.splitlines()) if k.strip()}
    print(f'\n  downstream {rel} under the FIX: {len(rows)} rows, check={check(rel)}')
    globals()[os.path.basename(rel).split('.')[0] + '_fixed'] = rows


if __name__ == '__main__':
  main()