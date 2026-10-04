#!/usr/bin/env python3
"""debug-gate-control.py -- MAKE THE LEVELS 4..7 GATE GO RED, ON PURPOSE.

    .venv/bin/python .agents/slop/debug-gate-control.py

A GATE NEVER SEEN RED IS NOT KNOWN TO WORK. `debug-gate.sh` going from five levels to
nine is 17 new rows plus a new digest guard, and NEITHER has ever failed, so every claim
this file makes about them is a claim about untested code. This plants one difference per
new level and requires the REAL `debug-gate.sh` to notice, naming the row.

THE CONTROLS, and what each is FOR:

  C1 clean      the unpatched tree agrees                                    -> rc 0
  C2  at L=4    `env_ge4` forced to threshold 5                             -> rc 1, names env_ge4
  C3  at L=5    `env_ge5` forced to threshold 6                             -> rc 1, names env_ge5
  C4  at L=6    `env_ge6` forced to threshold 7                             -> rc 1, names env_ge6
  C5  at L=7    `env_ge7` forced to threshold 8                             -> rc 1, names env_ge7
  C6  invariant a LEVEL-INVARIANT row made level-DEPENDENT                  -> rc 2, NOT 1
  C7  restore   every LIVE file byte-identical to where it started          -> md5 equal
  C8  constant  a level-invariant row wrong AT EVERY LEVEL                  -> rc 1, NOT 2

C6 AND C8 ARE THE TWO GUARDS, AND THEY COVER DIFFERENT FAILURES. C6's exit code is
DIFFERENT ON PURPOSE: the digest guard does not return a verdict about the port -- it says
the cross-level comparison is not well-posed, which is a failure of the harness's own
premise. Exiting 1 would report it as a disagreement and send a reader hunting a port bug
that does not exist. `graphcmp` already draws exactly this line ("exit 2 -- NOT WELL-POSED,
and this is NOT a verdict") and this reuses its convention rather than inventing a third
one. C8 is the complement: a value wrong at EVERY level digests identically at every level,
so the digest guard is blind to it BY CONSTRUCTION and the per-level CPython diff is what
catches it. Running both is what establishes that neither guard is redundant.

TWO ATTEMPTS AT C6 FAILED BEFORE THIS ONE, and both failures are in the notes at the plant
itself, because a plant that tests the wrong failure is worse than no plant: it reports
green. The first tested correctness instead of well-posedness; the second tested only one
lane, so the per-level diff answered before the digest was reached.

`pin_rows()` TAKES NO LEVEL, so a level cannot reach the pin as the file stands -- which is
the "held fixed BY CONSTRUCTION" half of the method doing its job. C6 has to PLANT that
reach precisely because it is otherwise inexpressible, on BOTH lanes, and that is the
honest shape of this control: it manufactures the one code path the design forbids, in
order to check that the digest notices when it exists.

THE LIVE TREE IS NEVER PATCHED. `agent-core.md`: "NEVER patch the live tree from a
harness", and four agents have lost work to uncommitted-state loss today. So the substrate
is COPIED to `.agents/slop/debug-control-work/`, every patch lands THERE, and the copy is
removed at the end. The live files' md5s are taken BEFORE and AFTER and asserted equal --
that is C7, and it is the assertion that makes the rest of this file trustworthy.

WHY THE TOOLS ARE SYMLINKED RATHER THAN COPIED. `debug-gate.sh` does
`cd "$(dirname "$0")/../.."`, so a COPY of the script under the scratch lands `cd` on the
scratch and then needs `bin/bend`, `.venv/bin/python` and `tinygrad/`. Those three are
symlinked to the live ones: the interpreter, the compiler and the UPSTREAM python must be
the same ones the real gate uses, and a second copy of any of them would be testing a
different gate. `tinybendygrad/` is a real copy, because that is the thing being mutated.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WORK = os.path.join(ROOT, '.agents', 'slop', 'debug-control-work')
WATCH = ['.agents/slop/debug-gate.bend', '.agents/slop/debug-gate.py',
         '.agents/slop/debug-gate.sh']
# What the scratch gate is run with. ONE level per control, because a control costs a
# three-lane bend run per level and the point is that the gate notices, not that it is
# slow. C6 gets TWO levels because the digest guard is defined over a SET of levels.
SINGLE = "%s"
INVARIANT_PRE = re.compile(r"^(gi_|mem_mb_|thr_|pin_|fires_|st_ok)")


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
  for f in ('debug-gate.bend', 'debug-gate.py', 'debug-gate.sh'):
    shutil.copy(os.path.join(ROOT, '.agents', 'slop', f),
                os.path.join(WORK, '.agents', 'slop', f))
  for link, target in (('bin', 'bin'), ('.venv', '.venv'), ('tinygrad', 'tinygrad')):
    os.symlink(os.path.join(ROOT, target), os.path.join(WORK, link))


def gate(levels):
  """Run the REAL debug-gate.sh over the scratch tree at `levels`. -> (rc, output)"""
  env = dict(os.environ)
  env.pop('DEBUG', None)
  env.pop('PYTHONPATH', None)
  env['DEBUG_GATE_LEVELS'] = levels
  p = subprocess.run(['sh', os.path.join(WORK, '.agents', 'slop', 'debug-gate.sh')],
                     cwd=ROOT, env=env, capture_output=True, text=True)
  return p.returncode, p.stdout + p.stderr


def invariant_digest(rows):
  sel = sorted(l for l in rows.split('\n') if INVARIANT_PRE.match(l))
  return hashlib.md5("\n".join(sel).encode()).hexdigest(), len(sel)


def main():
  before = watch()
  build_work()
  path = os.path.join(WORK, '.agents', 'slop', 'debug-gate.bend')
  with open(path) as f:
    green = f.read()
  fails = []

  # --- C1 clean ---------------------------------------------------------------------
  rc, out = gate("4")
  print("C1 clean at level 4: rc=%d, '3 lanes identical' printed: %s"
        % (rc, "3 lanes identical" in out))
  if rc != 0:
    fails.append("C1 the CLEAN tree did not agree at level 4 (rc=%d)" % rc)
  clean = invariant_digest(out)

  # --- C2..C5, one planted difference per new level ---------------------------------
  # `env_ge<L>` is forced to read threshold `L+1`, so at DEBUG=L the Bend lane answers 0
  # where CPython answers 1. This row is chosen because its expected value comes straight
  # off the live ContextVar on BOTH sides, so the disagreement is about the LEVEL and not
  # about a fixture, and because it is EXCLUDED from the invariant digest -- the
  # environment is exactly what is allowed to move between levels.
  for level in (4, 5, 6, 7):
    cid = level - 2   # C2..C5, so the labels do not collide with C6/C7/C8
    old = '    _ : Unit <- urow("env_ge%d", fired_of_ge(d, %d))' % (level, level)
    new = '    _ : Unit <- urow("env_ge%d", fired_of_ge(d, %d))  ' \
          '# PLANTED threshold L+1' % (level, level + 1)
    if green.count(old) != 1:
      fails.append("C%d the env_ge%d pattern occurs %d times, expected 1"
                   % (cid, level, green.count(old)))
      continue
    with open(path, 'w') as f:
      f.write(green.replace(old, new, 1))
    rc, out = gate(SINGLE % level)
    named = re.search(r"^[-+ ]*env_ge%d=" % level, out, re.M) is not None
    print("C%d planted at level %d: rc=%d, diff NAMES env_ge%d: %s"
          % (cid, level, rc, level, named))
    if rc != 1:
      fails.append("C%d rc was %d, expected 1" % (cid, rc))
    if not named:
      fails.append("C%d BROKEN but did NOT name env_ge%d" % (cid, level))
    if invariant_digest(out) != clean:
      fails.append("C%d the level-invariant digest MOVED, so `env_ge*` is in the digest "
                   "when it must not be -- the digest would be measuring the environment"
                   % cid)
    with open(path, 'w') as f:
      f.write(green)

  # --- C6 the digest guard ------------------------------------------------------------
  # TWO PLANTS WERE WRONG BEFORE THIS ONE, AND BOTH ERRORS ARE THE POINT.
  #
  # (i) `pin_bufs` was DOUBLED (`mem_len + mem_len`, so 10 not 5). Wrong at EVERY level,
  #     and a value wrong at every level digests to the SAME thing at every level, so the
  #     guard correctly stayed silent. The guard is about CROSS-LEVEL WELL-POSEDNESS, not
  #     correctness. C8 is the control for the constant case.
  #
  # (ii) `pin_bufs` was made level-dependent on the BEND SIDE ONLY. The Bend lane then
  #     disagreed with CPython at every level and the PER-LEVEL DIFF exited 1 before
  #     `check_digests` was ever reached -- so the control measured the OTHER guard and
  #     printed "the digest guard did not fire", which was true and beside the point.
  #
  # (iii) Both sides were then given `+ <the live DEBUG>`, and it STILL failed, because
  #     `main()` reads the pin with `child(None, MEM_BODY)` -- at DEBUG UNSET, on purpose.
  #     `DEBUG.value` inside that child is 0 whatever the process's environment says, so
  #     the Python plant was a no-op and the Bend lane alone moved. The Python half of the
  #     plant therefore has to be the line that RUNS THE PIN CHILD, not the line that
  #     prints it.
  #
  # (iv) With both halves correct the file no longer PARSED -- the Bend bind was at the top
  #     of the `def` body rather than inside the `do` block -- so the bend lane printed
  #     ZERO rows, `run_lane` retried 25 times and gave up, and the control read that as
  #     "the digest guard did not fire" when in fact nothing had run at all.
  #
  # The plant goes on BOTH LANES. The per-level diff then PASSES -- both sides moved
  # together -- while the level-INVARIANT digest still DIFFERS across levels, which is
  # exactly the condition the guard exists to refuse and exactly the one no other check in
  # this gate can see.
  #
  # FOUR VERSIONS BEFORE THE ONE THAT WORKS. The recurring lesson is that a broken plant
  # and a broken control are indistinguishable from the outside: a plant that does not
  # compile is a lane that prints nothing, and a lane that prints nothing is a ZERO-ROW
  # RESULT, which is indistinguishable from "not started". So this control REQUIRES the
  # planted run to report its row count (see the `89 rows` check below), and a control that
  # cannot tell "the guard did not fire" from "nothing ran" is not a control.
  bend_old_head = 'def pin_rows() -> IO(Unit):\n  do IO<Unit>:\n'
  # THE BIND GOES INSIDE THE `do` BLOCK, and that is a MEASURED Bend rule rather than a
  # formatting choice: an `IO`-returning bind (`x : T <- eff`) is only legal inside a
  # `do` block, while a PURE bind (`+r = f(x)`) is legal at the top of a `def` body
  # (`memory.bend`'s `p_count` is the example). The two are NOT interchangeable. With the
  # bind at the top of the body the whole file fails to parse -- "expected : 'def', 'type'
  # or 'law' / observed : ':'" -- so the lane printed zero rows and the control could not
  # tell that from a guard that stayed silent.
  bend_new_head = ('def pin_rows() -> IO(Unit):\n  do IO<Unit>:\n'
                   '    d : U32 <- H.debug()  # PLANTED\n')
  bend_old_row = '    _ : Unit <- urow("pin_bufs", M.mem_len(M.Planned.bs(p)))'
  bend_new_row = ('    _ : Unit <- urow("pin_bufs", U32.add(M.mem_len(M.Planned.bs(p)), d))'
                  '  # PLANTED')
  py_path = os.path.join(WORK, '.agents', 'slop', 'debug-gate.py')
  with open(py_path) as f:
    py_green = f.read()
  # THE PYTHON HALF OF THE PLANT IS THE LINE THAT RUNS THE PIN CHILD, not the print.
  # `main()` reads the pin with `child(None, MEM_BODY)` -- at DEBUG UNSET, deliberately,
  # because that is the Python half of "held fixed BY CONSTRUCTION". So adding
  # `+ DEBUG.value` to the print alone is a NO-OP (the value is 0 in that child) and the
  # Bend lane still disagreed at level 7 and the per-level diff answered first. The plant
  # that works is the one that removes the construction: run the pin child at the CURRENT
  # level and add the live ContextVar. That is precisely the code path the design forbids,
  # which is what makes it the right thing to plant.
  py_old = '  for l in keep(child(None, MEM_BODY), "pin"):'
  py_new = ('  for l in keep(child(level, MEM_BODY), "pin"):  # PLANTED: the pin now\n'
            '    # reads the level, which is the code path "held fixed" forbids.')
  py_old_row = 'print("pin_bufs=%d" % CAP["bufs"])'
  py_new_row = ('from tinygrad.helpers import DEBUG  # PLANTED\n'
                'print("pin_bufs=%d" % (CAP["bufs"] + DEBUG.value))')
  if (green.count(bend_old_head) != 1 or green.count(bend_old_row) != 1
          or py_green.count(py_old) != 1 or py_green.count(py_old_row) != 1):
    fails.append("C6 a plant pattern is not unique: bend head/row %d/%d, py call/row "
                 "%d/%d" % (green.count(bend_old_head), green.count(bend_old_row),
                            py_green.count(py_old), py_green.count(py_old_row)))
  else:
    with open(path, 'w') as f:
      f.write(green.replace(bend_old_head, bend_new_head, 1)
                   .replace(bend_old_row, bend_new_row, 1))
    with open(py_path, 'w') as f:
      f.write(py_green.replace(py_old, py_new, 1).replace(py_old_row, py_new_row, 1))
    rc, out = gate("unset 7")
    fired = "level-INVARIANT rows DIFFER" in out
    ran = "89 rows, 3 lanes identical" in out
    print("C6 a LEVEL-INVARIANT row made level-dependent ON BOTH LANES: rc=%d "
          "(expected 2), both lanes RAN (%s), digest guard fired: %s, called a FAILURE "
          "not a verdict: %s" % (rc, ran, fired, "NOT A VERDICT" in out))
    if not ran:
      fails.append("C6 the planted run did not produce its rows, so this control could "
                   "not tell 'the guard stayed silent' from 'nothing ran'")
    if rc != 2:
      fails.append("C6 rc was %d, expected 2 (the digest guard's own exit code), not 1"
                   % rc)
    if not fired:
      fails.append("C6 the digest guard did NOT fire on a level-dependent invariant row, "
                   "so it cannot see a level reaching the fixture")
    if "DISAGREE at level" in out:
      fails.append("C6 the per-level diff ALSO fired, so this control did not isolate "
                   "the digest guard")
    with open(path, 'w') as f:
      f.write(green)
    with open(py_path, 'w') as f:
      f.write(py_green)

  # --- C8 the OTHER guard, and why it needs its own control ---------------------------
  # A level-invariant row that is wrong AT EVERY LEVEL is invisible to the digest guard
  # and must be caught by the ordinary per-level CPython diff. Both plants change
  # `pin_bufs` at every level and only one of them; exactly one of them must be rc=2 and
  # exactly one must be rc=1, and together they are the statement that the two guards
  # cover different failures and neither is redundant.
  old_row = '    _ : Unit <- urow("pin_bufs", M.mem_len(M.Planned.bs(p)))'
  new_row = ('    _ : Unit <- urow("pin_bufs", U32.add(M.mem_len(M.Planned.bs(p)),\n'
             '      M.mem_len(M.Planned.bs(p))))  # PLANTED: wrong at every level')
  with open(path, 'w') as f:
    f.write(green.replace(old_row, new_row, 1))
  rc, out = gate("4")
  named = re.search(r"^[-+ ]*pin_bufs=", out, re.M) is not None
  print("C8 a level-invariant row wrong AT EVERY LEVEL: rc=%d (expected 1), diff names "
        "pin_bufs: %s -- the digest guard correctly stayed silent here"
        % (rc, named))
  if rc != 1:
    fails.append("C8 rc was %d, expected 1 (the per-level CPython diff)" % rc)
  if not named:
    fails.append("C8 BROKEN but did NOT name pin_bufs")
  with open(path, 'w') as f:
    f.write(green)

  # --- C7 restore, byte-identical -----------------------------------------------------
  for w in WATCH:
    now = digest(os.path.join(ROOT, w))
    if now != before[w]:
      fails.append("C7 the LIVE tree was modified: %s %s -> %s" % (w, before[w], now))
  ok7 = not any(f.startswith("C7") for f in fails)
  print("C7 every LIVE file byte-identical after all plants: %s" % ("yes" if ok7 else "NO"))

  shutil.rmtree(WORK)
  print("")
  if fails:
    print("CONTROLS FAILED, %d:" % len(fails))
    for f in fails:
      print("  FAIL", f)
    return 1
  print("ALL CONTROLS PASS -- the gate has been seen RED at levels 4, 5, 6 and 7, and "
        "the digest guard has been seen firing with its own exit code.")
  return 0


if __name__ == '__main__':
  sys.exit(main())