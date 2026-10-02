#!/usr/bin/env python3
"""Diff the two lanes of tinybendygrad/runtime/support/hcq2.bend against the
CPython oracle, and against each other.

    .venv/bin/python .agents/slop/hcq2-diff.py

Lane order is the one the brief demands: interpreted, native, CPython. The
oracle is `.agents/slop/hcq2-oracle.py` and it CALLS hcq2.py with DEV=NULL, so
no device is present. Nothing here is hand-typed on either side.
"""
import subprocess, sys, os, tempfile, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / 'tinybendygrad/runtime/support/hcq2.bend'
PY = ROOT / '.venv/bin/python'
ORACLES = [ROOT / '.agents/slop/hcq2-oracle.py', ROOT / '.agents/slop/hcq2-oracle2.py']

def run(cmd, **kw):
  return subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=900, **kw)

CACHE = pathlib.Path(tempfile.gettempdir()) / 'hq2-lane-cache'
def _lane(name, build, run_):
  """Each lane is built once and its OUTPUT cached under a name, because a
  timeout in the middle of a diff loses the whole run."""
  CACHE.mkdir(exist_ok=True)
  out = CACHE / f'{name}.bin'
  txt = CACHE / f'{name}.txt'
  if not out.exists() or not txt.exists() or run_[0] == '-r':
    b = run(build)
    if b.returncode: return b
    out.write_bytes(b.stdout)
    r = run([str(out)])
    txt.write_text(r.stdout)
  class R: pass
  r = R(); r.returncode = 0; r.stdout = txt.read_text(); r.stderr = ''
  return r

def lane_interp():
  return run(['./bin/bend', str(BEND)])

def lane_native():
  return _lane('native', ['./bin/bend', str(BEND), '-o', '-'], ['./bin/bend', '-r'])

def lane_cpython():
  env = dict(os.environ, DEV='NULL')
  out = ''
  for o in ORACLES:
    r = subprocess.run([str(PY), str(o)], capture_output=True, text=True, cwd=ROOT,
                       timeout=900, env=env)
    if r.returncode:
      print('ORACLE', o.name, 'FAILED rc', r.returncode, r.stderr[-800:])
      return r
    out += r.stdout
  return type('R', (), {'returncode': 0, 'stdout': out, 'stderr': ''})()

def rows(text):
  out = {}
  for line in text.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      out[k] = v
  return out

def main():
  checks = run(['./bin/bend', str(BEND), '--check-only'])
  print('CHECK:', checks.stdout.strip().splitlines()[0] if checks.stdout else checks.stderr[:200])
  li, ln, lc = lane_interp(), lane_native(), lane_cpython()
  if li.returncode: print('INTERPRETED LANE FAILED rc', li.returncode, li.stderr[-800:]); return 1
  if ln.returncode: print('NATIVE LANE FAILED rc', ln.returncode, ln.stderr[-800:]); return 1
  if lc.returncode: print('ORACLE FAILED rc', lc.returncode, lc.stderr[-800:]); return 1
  I, N, C = rows(li.stdout), rows(ln.stdout), rows(lc.stdout)
  print(f'rows: interpreted={len(I)} native={len(N)} cpython={len(C)}')

  only_i = sorted(set(I) - set(C)); only_c = sorted(set(C) - set(I))
  dis = sorted(k for k in set(I) & set(C) if I[k] != C[k])
  print(f'\nCpython-only rows ({len(only_c)}) -- the port has no counterpart yet:')
  for k in only_c: print(f'  {k}={C[k]}')
  print(f'\nBend-only rows ({len(only_i)}) -- no CPython counterpart:')
  for k in only_i: print(f'  {k}={I[k]}')
  print(f'\nDISAGREEMENTS ({len(dis)}):')
  for k in dis: print(f'  {k}: bend={I[k]!r} cpython={C[k]!r}')

  # lane 1 vs lane 2, on the SAME names
  ni, nn = sorted(set(I) - set(N)), sorted(set(N) - set(I))
  dl = sorted(k for k in set(I) & set(N) if I[k] != N[k])
  print(f'\nLANE DIFF interp vs native: interp-only={len(ni)} native-only={len(nn)} value-disagreements={len(dl)}')
  for k in ni[:20]: print(f'  interp-only {k}')
  for k in nn[:20]: print(f'  native-only {k}')
  for k in dl[:20]: print(f'  differs {k}: interp={I[k]!r} native={N[k]!r}')
  bad = len(dis) + len(ni) + len(nn) + len(dl)
  print(f'\n== {"OK" if bad == 0 else str(bad) + " PROBLEMS"} ==')
  return 0 if bad == 0 else 1

if __name__ == '__main__':
  sys.exit(main())