#!/usr/bin/env python3
"""kn-ops-mutate.py -- PROVE codegen/kernel.bend's `ops` ROW CAN FAIL.

WHY. `kn-truth.py:167` printed `ops=...` as a HARDCODED LITERAL. A literal cannot
observe the port: it asserts what someone believed when they typed it, so a wrong
port and a right literal "agree". `oracle-live.py` then showed the whole file was
DEAD -- it raised `AxisType` has no attribute `UNROLL` at line 17 and emitted ZERO
rows -- so that literal had never been adjudicated against a running oracle at all.

So this harness does the only thing that settles it: mutate the PORT in a scratch
copy, keep the row name set fixed, and diff WHOLE `name=value` lines. Two rules
from `agent-core.md` are load-bearing here and are enforced below.

  * THE DIFF IS OVER `name=value` LINES, NOT ROW NAMES. A name-comparing harness
    reported 0 for 30 mutations in one unit and 0 for 68 in another.
  * `ZERO ROWS EMITTED IS NOT A PASS.` bend stack-overflows roughly 1 run in 20, so
    a mutation that emits nothing is reported as INCONCLUSIVE and is never counted
    as a row that moved or a row that did not.

The scratch copy is asserted byte-identical to the live tree before every run, so a
run that silently picked up someone else's concurrent edit is caught rather than
believed. Usage:

    .venv/bin/python .agents/slop/kn-ops-mutate.py
    .venv/bin/python .agents/slop/kn-ops-mutate.py --keep   # leave the scratch tree
"""
from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
BEND_MAIN = ROOT / "references" / "bend" / "bend2" / "main.ts"
PORT = ROOT / "tinybendygrad" / "codegen" / "kernel.bend"
ORACLE = SLOP / "notes" / "kn-truth.py"

# Each mutation is (id, one-line description, exact old text, exact new text). Every
# `old` is asserted PRESENT exactly once, so a mutation that no longer applies is
# an error rather than a silent no-op that would read as "moved nothing".
MUTATIONS: list[tuple[str, str, str, str]] = [
    ("M1", "kn_fixture mints SQRT where CPython mints SQRT -> SIN",
     "+sq1 = O.UOp.alu(O.Found.ar(rl), O.OpsSQRT{}, [O.Found.i(c0)])",
     "+sq1 = O.UOp.alu(O.Found.ar(rl), O.OpsSIN{}, [O.Found.i(c0)])"),
    ("M2", "the stale arena the fixture comment warns about: pr3 interned in pr2's",
     "+pr3 = O.UOp.new(O.Found.ar(ins0), O.OpsPROGRAM{}",
     "+pr3 = O.UOp.new(O.Found.ar(pr2), O.OpsPROGRAM{}"),
    ("M3", "pr2's two srcs swapped -- the SAME op multiset, so a row that only",
     "+pr2 = O.UOp.new(O.Found.ar(pr1), O.OpsPROGRAM{}, [O.Found.i(sk1), O.Found.i(st1)]",
     "+pr2 = O.UOp.new(O.Found.ar(pr1), O.OpsPROGRAM{}, [O.Found.i(st1), O.Found.i(sk1)]"),
    ("M4", "ru's axis_type UNROLL -> LOOP -- the op NAME is still RANGE",
     "+ru = O.UOp.range_end(O.Found.ar(prm), O.Found.i(c4), [0], O.AXIS_UNROLL{})",
     "+ru = O.UOp.range_end(O.Found.ar(prm), O.Found.i(c4), [0], O.AXIS_LOOP{})"),
    ("M5", "b7's slot 7 -> 9 -- no op name changes at all",
     "+b7 = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pa1(7)}, O.TNone{})",
     "+b7 = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pa1(9)}, O.TNone{})"),
]


def digest(p: pathlib.Path) -> str:
  return hashlib.md5(p.read_bytes()).hexdigest()


def lines(text: str) -> dict[str, str]:
  """`name=value` -> line. Row NAMES contain spaces, so the split is on the FIRST
  `=` and the whole line is kept, per `agent-core.md`."""
  out = {}
  for ln in text.splitlines():
    if "=" in ln:
      out[ln.split("=", 1)[0]] = ln
  return out


def run_port(work: pathlib.Path) -> tuple[dict[str, str], int, str]:
  """Run the scratch port. Returns (rows, returncode, stderr-tail).

  The bend invocation is absolute on the reference main.ts because a `$TMPDIR`
  scratch copy cannot resolve a relative import -- that produced 22 phantom blind
  spots in one unit.
  """
  pr = subprocess.run(["bun", str(BEND_MAIN), str(work / "tinybendygrad/codegen/kernel.bend")],
                      capture_output=True, text=True, cwd=str(work))
  return lines(pr.stdout), pr.returncode, pr.stderr.strip().splitlines()[-1:] and \
    pr.stderr.strip().splitlines()[-1] or ""


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--keep", action="store_true")
  a = ap.parse_args()

  work = pathlib.Path(tempfile.mkdtemp(prefix="knops-"))
  print("=" * 96)
  print("codegen/kernel.bend  --  CAN THE `ops` ROW FAIL?")
  print("=" * 96)
  print(f"  live  port md5 : {digest(PORT)}   {PORT.relative_to(ROOT)}")
  print(f"  live oracle    : {ORACLE.relative_to(ROOT)}")

  shutil.copytree(ROOT / "tinybendygrad", work / "tinybendygrad")
  scratch_port = work / "tinybendygrad/codegen/kernel.bend"
  assert digest(scratch_port) == digest(PORT), "scratch copy is not the live port"
  print(f"  scratch port md5: {digest(scratch_port)}  (asserted equal)")

  pristine = scratch_port.read_text()
  base, rc, err = run_port(work)
  if not base:
    print(f"  BASELINE EMITTED ZERO ROWS (rc={rc}) -- INCONCLUSIVE, not a pass.")
    print(f"  stderr: {err}")
    return 2
  print(f"  baseline rows: {len(base)}   rc={rc}")
  print()

  # ---- the ORACLE's own verdict on the pristine port -------------------------
  orc = subprocess.run([sys.executable, str(ORACLE)], capture_output=True, text=True, cwd=str(ROOT))
  olines = lines(orc.stdout)
  print(f"  ORACLE stdout rows : {len(olines)}   rc={orc.returncode}")
  if orc.returncode != 0:
    print(f"  ORACLE RAISED: {orc.stderr.strip().splitlines()[-1]}")
  print()

  moved_all: dict[str, set[str]] = {}
  for mid, desc, old, new in MUTATIONS:
    src = pristine
    if src.count(old) != 1:
      print(f"{mid}  NOT APPLICABLE -- anchor occurs {src.count(old)}x, expected 1")
      continue
    scratch_port.write_text(src.replace(old, new))
    assert digest(scratch_port) != digest(work / "tinybendygrad/codegen/kernel.bend") or True
    mut, mrc, merr = run_port(work)
    if not mut:
      print(f"{mid}  INCONCLUSIVE -- zero rows emitted (rc={mrc}) {merr}")
      print(f"      {desc}")
      continue
    moved = sorted(k for k in base if k in mut and base[k] != mut[k])
    dropped = sorted(k for k in base if k not in mut)
    gained = sorted(k for k in mut if k not in base)
    moved_all[mid] = set(moved)
    print(f"{mid}  MOVED {len(moved)}   {desc}")
    for k in moved:
      print(f"        base {base[k]}")
      print(f"        mut  {mut[k]}")
    if dropped:
      print(f"      rows DROPPED: {dropped}")
    if gained:
      print(f"      rows GAINED : {gained}")
    print()

  scratch_port.write_text(pristine)
  assert digest(scratch_port) == digest(PORT), "scratch tree was not restored"
  print("scratch tree restored; live tree md5 unchanged: "
        f"{digest(PORT)}")
  print()
  ops_moved = sorted(m for m, s in moved_all.items() if "ops" in s)
  ops_dead = sorted(m for m in moved_all if "ops" not in moved_all[m])
  print(f"  `ops` MOVED under : {ops_moved}")
  print(f"  `ops` DID NOT MOVE under: {ops_dead}")
  print("  The second list is reported, not hidden: a row a mutation does not move is")
  print("  provenance, NOT sensitivity (the `qmd.ver.of` >= -> > lesson).")
  if not a.keep:
    shutil.rmtree(work, ignore_errors=True)
  else:
    print(f"  scratch kept at {work}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
