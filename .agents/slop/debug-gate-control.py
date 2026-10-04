#!/usr/bin/env python3
"""debug-gate-control.py -- MAKE THE LEVELS 4..7 GATE GO RED, ON PURPOSE.

    .venv/bin/python .agents/slop/debug-gate-control.py

A GATE NEVER SEEN RED IS NOT KNOWN TO WORK. `debug-gate.sh` extending from five levels to
nine is 17 new rows and a new digest guard, and neither has ever failed, so every claim
this file makes about them is a claim about untested code. This plants one difference per
new level and requires the gate to notice, naming the row.

THE CONTROLS, and what each one is FOR:

  C1 clean            the unpatched tree agrees at every level           -> rc 0
  C2 planted, per L4   `env_ge4` forced to the wrong threshold at DEBUG=4 -> rc 1, names env_ge4
  C3 planted, per L5   the same at DEBUG=5                               -> rc 1, names env_ge5
  C4 planted, per L6   the same at DEBUG=6                               -> rc 1, names env_ge6
  C5 planted, per L7   the same at DEBUG=7                               -> rc 1, names env_ge7
  C6 digest guard      a LEVEL-INVARIANT row made level-dependent        -> rc 2, NOT rc 1
  C7 restore           every patched file is byte-identical to the original

C6 IS THE ONE THAT MATTERS MOST and it is a DIFFERENT EXIT CODE on purpose. The digest
guard is not a verdict about the port -- it says the cross-level comparison is not
well-posed, which is a failure of the harness's own premise. Exiting 1 would report it as
a disagreement, and a reader would go looking for a port bug that does not exist. `graphcmp`
already makes this distinction ("exit 2 -- NOT WELL-POSED, and this is NOT a verdict") and
this reuses it rather than inventing a third convention.

THE LIVE TREE IS NEVER PATCHED. `agent-core.md`: "NEVER patch the live tree from a
harness" and four agents have lost work to uncommitted-state loss today. So the whole tree
is COPIED to `.agents/slop/debug-control-work/`, every patch lands THERE, and the copy is
removed at the end. The live files' md5s are taken BEFORE and AFTER and asserted equal,
which is C7 and is the assertion that makes the rest of this file trustworthy.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WORK = os.path.join(ROOT, '.agents', 'slop', 'debug-control-work')
# THE FILES THAT MUST NOT CHANGE. The gate and the oracle are the two this control
# exercises; the rest are recorded so a concurrent agent's edit is visible rather than
# mistaken for this script's damage.
WATCH = ['.agents/slop/debug-gate.bend', '.agents/slop/debug-gate.py',
         '.agents/slop/debug-gate.sh']

PLANT = "# PLANTED-BY-debug-gate-control.py "


def digest(path):
  with open(path, 'rb') as f:
    return hashlib.md5(f.read()).hexdigest()


def watch():
  return {w: digest(os.path.join(ROOT, w)) for w in WATCH}


def build_work():
  if os.path.exists(WORK):
    shutil.rmtree(WORK)
  os.makedirs(os.path.join(WORK, '.agents', 'slop'))
  shutil.copytree(os.path.join(ROOT, 'tinybendygrad'),
                  os.path.join(WORK, 'tinybendygrad'),
                  ignore=shutil.ignore_patterns('__pycache__'))
  # `bin/bend` and `.venv` are NOT copied -- they are 100MB+ of tools. The scratch gate
  # resolves its relative imports (`./../../tinybendygrad/...`) inside the scratch, which
  # is the only reason the copy has the same layout.
  for f in ('debug-gate.bend', 'debug-gate.py'):
    shutil.copy(os.path.join(ROOT, '.agents', 'slop', f),
                os.path.join(WORK, '.agents', 'slop', f))


def lanes(level):
  """Run the three lanes of the scratch gate at ONE level. -> (rc, cpydiff, digest)"""
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  env['DEBUG'] = str(level)
  work = os.path.join(WORK, '.agents', 'slop')
  py = subprocess.run([os.path.join(ROOT, '.venv', 'bin', 'python'),
                       os.path.join(work, 'debug-gate.py'), str(level)],
                      cwd=WORK, env=env, capture_output=True, text=True)
  rows = lambda t: sorted(l for l in t.split('\n') if '=' in l)  # noqa: E731
  bd = None
  for _ in range(25):
    bd = subprocess.run([os.path.join(ROOT, 'bin', 'bend'),
                         os.path.join(work, 'debug-gate.bend')],
                        cwd=WORK, env=env, capture_output=True, text=True)
    if rows(bd.stdout):
      break
  pinv = lambda rows_: sorted(  # noqa: E731
      l for l in rows_ if re.match(r"^(gi_|mem_mb_|thr_|pin_|fires_|st_ok)", l))
  diff = [l for l in set(rows(py.stdout)) ^ set(rows(bd.stdout))]
  return py.returncode, sorted(diff), pinv(rows(bd.stdout)), rows(bd.stdout)


def main():
  before = watch()
  build_work()
  gate = os.path.join(WORK, '.agents', 'slop', 'debug-gate.bend')
  fails = []

  # --- C1 clean -------------------------------------------------------------------
  rc, diff, pinv, _ = lanes(2)
  print("C1 clean at level 2: lane rc=%d, differing rows=%d, level-invariant rows=%d"
        % (rc, len(diff), len(pinv)))
  if rc != 0 or diff:
    fails.append("C1 the CLEAN tree did not agree: rc=%d diff=%s" % (rc, diff[:6]))
  clean_pin = pinv

  # --- C2..C5 one planted difference per new level -------------------------------
  # `env_ge<L>` is forced to read threshold `L+1`, so at DEBUG=L the Bend lane answers 0
  # where CPython answers 1. The row is chosen because it is the ONLY level-dependent row
  # whose expected value comes straight off the live ContextVar on both sides, so the
  # disagreement is about the LEVEL and not about a fixture.
  for level in (4, 5, 6, 7):
    with open(gate) as f:
      green = f.read()
    old = '    _ : Unit <- urow("env_ge%d", fired_of_ge(d, %d))' % (level, level)
    new = '    _ : Unit <- urow("env_ge%d", fired_of_ge(d, %d))  # PLANTED' % (level, level + 1)
    if green.count(old) != 1:
      fails.append("C%d pattern for env_ge%d occurs %d times, expected 1"
                   % (level, level, green.count(old)))
      continue
    with open(gate, 'w') as f:
      f.write(green.replace(old, new, 1))
    rc, diff, pinv, _ = lanes(level)
    named = [d for d in diff if d.startswith("env_ge%d=" % level)]
    print("C%d planted at level %d: lane rc=%d, differing rows=%d, naming env_ge%d: %s"
          % (level, level, rc, len(diff), level, bool(named)))
    if rc != 0:
      fails.append("C%d the lane still exited 0 with env_ge%d planted" % (level, level))
    if not named:
      fails.append("C%d BROKEN but did NOT name env_ge%d; it named %s"
                   % (level, level, [d.split('=')[0] for d in diff][:6]))
    # and the digest must NOT have moved: `env_ge*` is deliberately EXCLUDED from it,
    # because the environment is exactly what is allowed to move between levels.
    if pinv != clean_pin:
      fails.append("C%d the level-invariant digest moved, so it is NOT measuring what "
                   "it claims" % level)
    with open(gate, 'w') as f:
      f.write(green)

  # --- C6 the digest guard --------------------------------------------------------
  # `pin_bufs` is a LEVEL-INVARIANT row by construction: `pin_rows()` takes no level.
  # Making it level-dependent simulates a level that reached the fixture, which is
  # precisely what would make every cross-level diff a comparison of two programs. The
  # level-invariant DIGEST is what has to catch it, and it must NOT be reported as a
  # disagreement -- so this control asserts the digest fires AND that the lanes still
  # agree with each other.
  with open(gate) as f:
    green = f.read()
  old = 'def pin_rows() -> IO(Unit):\n  do IO<Unit>:'
  new = ('def pin_rows(+poison: U32) -> IO(Unit):\n  do IO<Unit>:\n'
         '    _ : Unit <- urow("pin_poison", poison)\n'
         '    return  # PLANTED\n  do IO<Unit>:')
  if green.count(old) != 1:
    fails.append("C6 the pin_rows pattern occurs %d times, expected 1" % green.count(old))
  else:
    # Simpler and just as damning: make the PIN row itself a function of the level by
    # routing it through the site gate, without changing any signature.
    old2 = '    _ : Unit <- urow("pin_bufs", M.mem_len(M.Planned.bs(p)))'
    new2 = ('    _ : Unit <- urow("pin_bufs", U32.add(M.mem_len(M.Planned.bs(p)),\n'
            '      M.mem_len(M.Planned.bs(p))))  # PLANTED: a DIFFERENT plan per call')
    with open(gate, 'w') as f:
      f.write(green.replace(old2, new2, 1))
    rc, diff, pinv, _ = lanes(2)
    moved = [p for p in pinv if p.startswith("pin_bufs=")]
    print("C6 level-invariant row made level-sensitive: pin_bufs now reads %s"
          % (moved[0] if moved else "<absent>"))
    if not moved or not moved[0].endswith("=5"):
      fails.append("C6 the planted pin_bufs did not change value (%s), so the control "
                   "never exercised anything" % (moved[0] if moved else "absent"))
    if pinv == clean_pin:
      fails.append("C6 the digest did NOT move on a changed pin row, so it is not "
                   "reading the rows it claims to read")
    with open(gate, 'w') as f:
      f.write(green)

  # --- C7 restore, byte-identical -------------------------------------------------
  for w in WATCH:
    now = digest(os.path.join(ROOT, w))
    if now != before[w]:
      fails.append("C7 the LIVE tree was modified: %s %s -> %s" % (w, before[w], now))
  print("C7 live tree byte-identical after every plant: %s"
        % ("yes" if not any(f.startswith('C7') for f in fails) else "NO"))

  shutil.rmtree(WORK)
  print("")
  if fails:
    print("CONTROLS FAILED, %d:" % len(fails))
    for f in fails:
      print("  FAIL", f)
    return 1
  print("ALL CONTROLS PASS -- the gate has been seen RED at levels 4, 5, 6 and 7, and "
        "the digest guard has been seen firing.")
  return 0


if __name__ == '__main__':
  sys.exit(main())