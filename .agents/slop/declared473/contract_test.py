#!/usr/bin/env python3
"""Test the DECLARED-NAME contract on three of the 473.

Each case builds a SCRATCH mirror of the reader's own expected root under
`.agents/slop/declared473/tree/`, renames ONE target with `os.rename`, runs the reader
the reader-PLAN names, and reports BASELINE rc vs MUTATED rc. Nothing in the live tree moves.

  t1  target figurefix/plant/D-live/D0-run-summary.txt
      reader figurefix/plant/plant.py:54,58  (copytree D-live -> scratch, then read by name)
  t2  target figurefix/plant/D-live/D1-graph-matmul.txt   (a D-live file NOT read by name)
      reader the same plant.py  -- control: the contract should NOT cover it
  t3  target rerun/D-before/D0-run-summary.txt
      reader .agents/slop/devrecord/xcheck.py:46 (runs on ROOT/runs/graphcmp/D)
"""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
TREE = HERE / "tree"
PY = str(ROOT / ".venv/bin/python")


def mirror(t1: pathlib.Path):
    """Build a scratch repo root that plant.py can resolve (ROOT = HERE.parents[3])."""
    plant = t1 / ".agents/slop/figurefix/plant"
    plant.mkdir(parents=True)
    (t1 / "checks").mkdir(exist_ok=True)
    for f in ("corpus-figure.py", "devpin.py", "differ.py"):
        shutil.copy2(ROOT / "checks" / f, t1 / "checks" / f)
    shutil.copy2(ROOT / ".agents/slop/figurefix/plant/plant.py", plant / "plant.py")
    (t1 / ".agents/slop/graphcmp.py").symlink_to(ROOT / ".agents/slop/graphcmp.py")
    (t1 / ".venv").symlink_to(ROOT / ".venv")
    shutil.copytree(ROOT / ".agents/slop/figurefix/plant/D-live", plant / "D-live")


def run_plant(scratch: pathlib.Path):
    r = subprocess.run([PY, str(scratch / ".agents/slop/figurefix/plant/plant.py")],
                       capture_output=True, text=True, cwd=scratch)
    return r.returncode, (r.stdout + r.stderr).splitlines()[-3:]


def case_plant(scratch: pathlib.Path, target_rel: str):
    shutil.rmtree(scratch, ignore_errors=True)
    mirror(scratch)
    base_rc, base_tail = run_plant(scratch)
    p = scratch / target_rel
    os.rename(p, p.with_suffix(".rows"))
    mut_rc, mut_tail = run_plant(scratch)
    return base_rc, mut_rc, base_tail, mut_tail


def case_xcheck():
    """xcheck.py resolves LIVE = ROOT/runs/graphcmp/D; mirror that root depth."""
    scratch = TREE / "t3"
    shutil.rmtree(scratch, ignore_errors=True)
    (scratch / "checks").mkdir(parents=True)
    for f in ("corpus-figure.py", "devpin.py", "differ.py", "env-precond.py"):
        shutil.copy2(ROOT / "checks" / f, scratch / "checks" / f)
    (scratch / ".agents/slop").mkdir(parents=True)
    (scratch / ".agents/slop/graphcmp.py").symlink_to(ROOT / ".agents/slop/graphcmp.py")
    for dep in ("graphcmp-oracle.py", "graphcmp-p13-ops.py"):
        if (ROOT / ".agents/slop" / dep).exists():
            shutil.copy2(ROOT / ".agents/slop" / dep, scratch / ".agents/slop" / dep)
    (scratch / ".agents/slop/devrecord").mkdir()
    (scratch / ".venv").symlink_to(ROOT / ".venv")
    shutil.copy2(ROOT / ".agents/slop/devrecord/xcheck.py",
                 scratch / ".agents/slop/devrecord/xcheck.py")
    shutil.copytree(ROOT / ".agents/slop/rerun/D-before", scratch / "runs/graphcmp/D")
    def run():
        r = subprocess.run([PY, str(scratch / ".agents/slop/devrecord/xcheck.py")],
                           capture_output=True, text=True, cwd=scratch)
        return r.returncode, (r.stdout + r.stderr).splitlines()[-2:]
    base_rc, base_tail = run()
    p = scratch / "runs/graphcmp/D/D0-run-summary.txt"
    os.rename(p, p.with_suffix(".rows"))
    mut_rc, mut_tail = run()
    return base_rc, mut_rc, base_tail, mut_tail


def main():
    TREE.mkdir(exist_ok=True)
    print("=== t1  figurefix/plant/D-live/D0-run-summary.txt  (read by plant.py:58) ===")
    b, m, bt, mt = case_plant(TREE / "t1", ".agents/slop/figurefix/plant/D-live/D0-run-summary.txt")
    print(f"  baseline rc={b}  mutated rc={m}")
    print(f"  baseline tail: {bt}")
    print(f"  mutated  tail: {mt}")
    print("\n=== t2  figurefix/plant/D-live/D1-graph-matmul.txt  (NOT read by name) ===")
    b2, m2, bt2, mt2 = case_plant(TREE / "t2", ".agents/slop/figurefix/plant/D-live/D1-graph-matmul.txt")
    print(f"  baseline rc={b2}  mutated rc={m2}")
    print(f"  mutated  tail: {mt2}")
    print("\n=== t3  rerun/D-before/D0-run-summary.txt  (reader PLAN names xcheck.py:46) ===")
    b3, m3, bt3, mt3 = case_xcheck()
    print(f"  baseline rc={b3}  mutated rc={m3}")
    print(f"  baseline tail: {bt3}")
    print(f"  mutated  tail: {mt3}")
    return 0


sys.exit(main())
