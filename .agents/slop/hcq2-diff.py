#!/usr/bin/env python3
"""Diff the two lanes of tinybendygrad/runtime/support/hcq2.bend against the
CPython oracle, and against each other.

    .venv/bin/python .agents/slop/hcq2-diff.py [port.bend]

The port path is an argument so a harness can be tested against a perturbed COPY
of the port without editing the port: `hcq2.bend` belongs to a live agent, and a
gate you cannot break on purpose is a gate you have not tested. The copy must live
BESIDE the original, because a relative `import ./x.c` does not resolve from a
scratch directory.

Lane order is the one the brief demands: interpreted, native, CPython. The
authority is `.agents/slop/hcq2-oracle.py` + `-oracle2.py`, which CALL hcq2.py
with DEV=NULL, so no device is present.

THE NATIVE LANE USED TO BE DEAD AND IT SAID NOTHING. It ran
`bend <file> -o -` followed by `bend -r`: Bend 2.0.34 has NO `-r` option, and
`-o -` writes ZERO bytes because the backend is chosen by the output file's
EXTENSION. So the lane cached a 0-byte "binary", ran it, got nothing, and the
`rows: native=0` line read like a lane that had nothing to disagree about. An
absent check looks exactly like a passing check, so this file now asserts a row
count on EVERY lane and prints `LANE DID NOT RUN` with the reason when a lane
produces nothing -- including a lane whose CACHED artefact is 0 bytes, which is
how a dead lane survives a fix to the build command.
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / 'tinybendygrad/runtime/support/hcq2.bend'
PY = ROOT / '.venv/bin/python'
ORACLES = [ROOT / '.agents/slop/hcq2-oracle.py', ROOT / '.agents/slop/hcq2-oracle2.py']
CACHE = pathlib.Path(tempfile.gettempdir()) / 'hq2-lane-cache'


class LaneDead(Exception):
  """A lane that produced no rows. Never report this as a clean run."""


def target():
  return pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BEND


def run(cmd, **kw):
  return subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=900, **kw)


def lane_interp(port):
  r = run(['./bin/bend', str(port)])
  if r.returncode:
    raise LaneDead('INTERPRETED LANE DID NOT RUN rc %d\n%s' % (r.returncode, r.stderr[-800:]))
  return r.stdout


def lane_native(port):
  """`-o` selects the backend by EXTENSION, so the output must be named; `-o -`
  writes 0 bytes. Each cached artefact is size-checked: a 0-byte bin or a 0-row
  txt is the fingerprint of a lane that never ran, and reusing it is how this
  lane stayed dead after the build command was fixed."""
  CACHE.mkdir(exist_ok=True)
  out, txt = CACHE / f'{port.stem}.native.bin', CACHE / f'{port.stem}.native.txt'
  if not (out.exists() and out.stat().st_size and txt.exists() and txt.stat().st_size):
    b = run(['./bin/bend', str(port), '-o', str(out)])
    if b.returncode or not out.exists() or not out.stat().st_size:
      raise LaneDead('NATIVE LANE DID NOT RUN: build rc %d, %d bytes\n%s'
                     % (b.returncode, out.stat().st_size if out.exists() else 0, b.stderr[-800:]))
    out.chmod(0o755)
    txt.write_text(run([str(out)]).stdout)
  if not txt.stat().st_size:
    raise LaneDead('NATIVE LANE DID NOT RUN: the built binary printed 0 bytes '
                   '(cache %s is poisoned; delete it)' % txt)
  return txt.read_text()


def lane_cpython():
  env = dict(os.environ, DEV='NULL')
  out = ''
  for o in ORACLES:
    r = subprocess.run([str(PY), str(o)], capture_output=True, text=True, cwd=ROOT,
                       timeout=900, env=env)
    if r.returncode:
      raise LaneDead('ORACLE DID NOT RUN: %s rc %d\n%s' % (o.name, r.returncode, r.stderr[-800:]))
    out += r.stdout
  if not out.strip():
    raise LaneDead('ORACLE DID NOT RUN: every oracle printed nothing')
  return out


def rows(text):
  return {k: v for k, v in (ln.split('=', 1) for ln in text.splitlines() if '=' in ln)}


def main():
  port = target()
  checks = run(['./bin/bend', str(port), '--check-only'])
  print('CHECK:', checks.stdout.strip().splitlines()[0] if checks.stdout else checks.stderr[:200])
  print('AUTHORITY: %s -- live CPython calling hcq2.py with DEV=NULL'
        % ', '.join(o.name for o in ORACLES))
  try:
    I, N, C = rows(lane_interp(port)), rows(lane_native(port)), rows(lane_cpython())
  except LaneDead as e:
    print(e)
    return 1
  if not I or not N or not C:
    print('FAIL: a lane produced 0 rows -- interpreted=%d native=%d cpython=%d'
          % (len(I), len(N), len(C)))
    return 1
  print('rows: interpreted=%d native=%d cpython=%d  COMPARED interp-vs-cpython=%d '
        'interp-vs-native=%d' % (len(I), len(N), len(C), len(set(I) & set(C)), len(set(I) & set(N))))

  only_i, only_c = sorted(set(I) - set(C)), sorted(set(C) - set(I))
  dis = sorted(k for k in set(I) & set(C) if I[k] != C[k])
  print('\nCPython-only rows (%d) -- the port has no counterpart yet:' % len(only_c))
  for k in only_c: print('  %s=%s' % (k, C[k]))
  print('\nBend-only rows (%d) -- no CPython counterpart:' % len(only_i))
  for k in only_i: print('  %s=%s' % (k, I[k]))
  print('\nDISAGREEMENTS bend vs cpython (%d):' % len(dis))
  for k in dis: print('  %s: bend=%r cpython=%r' % (k, I[k], C[k]))

  ni, nn = sorted(set(I) - set(N)), sorted(set(N) - set(I))
  dl = sorted(k for k in set(I) & set(N) if I[k] != N[k])
  print('\nLANE DIFF interp vs native: interp-only=%d native-only=%d value-disagreements=%d'
        % (len(ni), len(nn), len(dl)))
  for k in ni[:20]: print('  interp-only %s' % k)
  for k in nn[:20]: print('  native-only %s' % k)
  for k in dl[:20]: print('  differs %s: interp=%r native=%r' % (k, I[k], N[k]))
  bad = len(dis) + len(ni) + len(nn) + len(dl)
  print('\n== %s ==' % ('OK' if bad == 0 else str(bad) + ' PROBLEMS'))
  return 0 if bad == 0 else 1


if __name__ == '__main__':
  sys.exit(main())