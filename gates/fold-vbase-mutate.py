#!/usr/bin/env python3
"""fold-vbase-mutate.py -- the PLANT for the `vb_` ROWS of
`tinybendygrad/uop/fold.bend`: the ways `unsharded_base`, `storage_base` and
`is_virtual` could be WRONG, each one applied and MEASURED.

    .venv/bin/python gates/fold-vbase-mutate.py

THE CONTRACT. Every mutation is a textual edit to a SCRATCH COPY of
`tinybendygrad/`, the copy is compiled, the `vb_` rows are diffed against the
baseline, and the rows that MOVED are printed BY NAME. A mutation that does
not compile is reported as such and is NEVER reported as "0 rows moved" --
the tree's own lesson is that a harness which cannot tell "the edit changed
nothing" from "the edit changed everything" is the defect.

WHY A SCRATCH TREE AND NOT THE WORKING COPY: `uop/ops.bend` and
`uop/symbolic.bend` belong to other units, and the tree's own ranges mutation
table records that editing in place raced with two other writers and a stale
baseline made every row look as if it moved. The copy is 12 MB and the whole
harness is one `shutil.copytree`.

THE PLANT, and each row is the failure mode it names:
  P1  the step reads the src's own `unsharded_base` instead of the src's `base`
  P2  the step set drops UNSHARD
  P3  the step set drops BITCAST and AFTER
  P4  the step reads the src's `base` instead of the src's `storage_base`
  P5  the weak set is `is_int` (drops weakfloat)
  P6  the weak set is `is_float` (drops weakint)
  P7  the device half of `is_virtual` is dropped
  P8  the device half of `is_virtual` is inverted
  P9  `unsharded_base`'s step set is conflated with `storage_base`'s
  P10 the two neighbours are EXCHANGED
  L1  a no-op edit -- THE CONTROL
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reporoot                                                    # noqa: E402

# THE ROOT, BY THE MARKER AND NOT BY A DEPTH. It used to be THREE `dirname`s, which is
# right for `.agents/slop/` and wrong for `gates/`, and a number that cannot be right for
# both is a number that will be wrong for one. `gates/reporoot.py` walks UP from this file
# until it finds a directory holding the markers `pyproject.toml`, `tinybendygrad/` and
# `tinygrad/`, so it is right wherever this file lives -- and a file that cannot find one
# exits 3, REFUSED, NOT A VERDICT, rather than measuring a tree it could not identify.
try:
  ROOT = reporoot.root(__file__)
except reporoot.RootNotFound as e:
  print(f"== REFUSED, NOT A VERDICT: {e}", file=sys.stderr)
  raise SystemExit(3)
SCRATCH = os.path.join(ROOT, ".agents", "slop", "vbase-mut")
FOLD_REL = os.path.join("tinybendygrad", "uop", "fold.bend")

# each mutation: (id, what it names, the exact old text, the exact new text)
MUTATIONS = [
  ("P1", "the step reads the src's own `unsharded_base`, not the src's `base`",
   "def unbase_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:\n  base_of.go(ss, i, unbase_of.steps(op))",
   "def src_unbase(k: U32, ss: List<&2, Derived>) -> U32:\n"
   "  Derived.unbase(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))\n\n"
   "def unbase_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:\n"
   "  Bool.pick(U32, unbase_of.steps(op), src_unbase(0, ss), i)"),
  ("P2", "the step set drops UNSHARD",
   "def unbase_of.steps(+op: O.Op) -> Bool:\n  Bool.or(base_of.steps(op), base_of.is_unshard(op))",
   "def unbase_of.steps(+op: O.Op) -> Bool:\n  base_of.steps(op)"),
  ("P3", "the step set drops BITCAST and AFTER",
   "def sbase_of.steps(+op: O.Op) -> Bool:\n"
   "  Bool.or(Bool.or(unbase_of.steps(op), base_of.is_bitcast(op)), base_of.is_after(op))",
   "def sbase_of.steps(+op: O.Op) -> Bool:\n  unbase_of.steps(op)"),
  ("P4", "the step reads the src's `base`, not the src's `storage_base`",
   "def sbase_of.go(ss: List<&2, Derived>, i: U32, steps: Bool) -> U32:\n"
   "  match steps:\n    case True{}: src_sbase(0, ss)\n    case False{}: i",
   "def sbase_of.go(ss: List<&2, Derived>, i: U32, steps: Bool) -> U32:\n"
   "  match steps:\n    case True{}: src_base(0, ss)\n    case False{}: i"),
  ("P5", "the weak set is `is_int`, so weakfloat is not weak",
   "def dt_is.is_weak(+d: S.Dt) -> Bool:\n  match d:\n"
   "    case S.Dt{_, _, S.CWeakInt{}, _}: True{}\n    case S.Dt{_, _, S.CWeakFloat{}, _}: True{}\n"
   "    case _: False{}",
   "def dt_is.is_weak(+d: S.Dt) -> Bool:\n  match d:\n"
   "    case S.Dt{_, _, S.CWeakInt{}, _}: True{}\n    case S.Dt{_, _, S.CSint{}, _}: True{}\n"
   "    case S.Dt{_, _, S.CUint{}, _}: True{}\n    case _: False{}"),
  ("P6", "the weak set is `is_float`, so weakint is not weak",
   "def dt_is.is_weak(+d: S.Dt) -> Bool:\n  match d:\n"
   "    case S.Dt{_, _, S.CWeakInt{}, _}: True{}\n    case S.Dt{_, _, S.CWeakFloat{}, _}: True{}\n"
   "    case _: False{}",
   "def dt_is.is_weak(+d: S.Dt) -> Bool:\n  match d:\n"
   "    case S.Dt{_, _, S.CWeakFloat{}, _}: True{}\n    case S.Dt{_, _, S.CFloat{}, _}: True{}\n"
   "    case _: False{}"),
  ("P7", "the device half of `is_virtual` is dropped",
   "def dev_none(m: Maybe<&2, S.Dev>) -> Bool:\n  match m:\n    case None{}: True{}\n    case _: False{}",
   "def dev_none(m: Maybe<&2, S.Dev>) -> Bool:\n  match m:\n    case _: False{}"),
  ("P8", "the device half of `is_virtual` is inverted",
   "def dev_none(m: Maybe<&2, S.Dev>) -> Bool:\n  match m:\n    case None{}: True{}\n    case _: False{}",
   "def dev_none(m: Maybe<&2, S.Dev>) -> Bool:\n  match m:\n    case _: True{}"),
  ("P9", "`unsharded_base`'s step set is conflated with `storage_base`'s",
   "def unbase_of.steps(+op: O.Op) -> Bool:\n  Bool.or(base_of.steps(op), base_of.is_unshard(op))",
   "def unbase_of.steps(+op: O.Op) -> Bool:\n"
   "  Bool.or(Bool.or(base_of.steps(op), base_of.is_unshard(op)), base_of.is_after(op))"),
  ("P10", "the two neighbours EXCHANGED -- `unbase` reads `sbase` and back",
   "        unbase_of(i, op, Srcs.ss(x)), sbase_of(i, op, Srcs.ss(x)),",
   "        sbase_of(i, op, Srcs.ss(x)), unbase_of(i, op, Srcs.ss(x)),"),
  ("L1", "a no-op edit -- THE CONTROL",
   "# `UOp.is_virtual` -- ops.py:891. `self.device is None or self.dtype in dtypes.weaks`",
   "# `UOp.is_virtual` -- ops.py:891. `self.device is None or self.dtype in dtypes.weaks`\n# THE CONTROL: a comment that changes nothing."),
]


def run_bend(path):
  """the `vb_` rows, or None if the file did not compile."""
  proc = subprocess.run([os.path.join(ROOT, "bin", "bend"), path],
                        cwd=ROOT, capture_output=True, text=True)
  if proc.returncode != 0:
    return None
  return {line.split()[0]: line for line in proc.stdout.splitlines() if line.startswith("vb_")}


def moved(base, got):
  if got is None:
    return None
  names = []
  for tag in base:
    if base[tag] != got.get(tag):
      names.append(tag)
  return names


def main():
  if os.path.exists(SCRATCH):
    shutil.rmtree(SCRATCH)
  os.makedirs(SCRATCH)
  shutil.copytree(os.path.join(ROOT, "tinybendygrad"), os.path.join(SCRATCH, "tinybendygrad"))
  target = os.path.join(SCRATCH, FOLD_REL)
  pristine = open(target).read()

  base = run_bend(target)
  if base is None:
    print("BASELINE DID NOT COMPILE -- the plant is not measurable")
    return 1
  print(f"baseline: {len(base)} rows")
  print()

  for mid, what, old, new in MUTATIONS:
    if old not in pristine:
      print(f"{mid} DID NOT APPLY -- the old text is not in the file. NOT REPORTED AS 0.")
      continue
    open(target, "w").write(pristine.replace(old, new, 1))
    got = run_bend(target)
    open(target, "w").write(pristine)
    if got is None:
      print(f"{mid} DID NOT COMPILE -- reported as such, never as '0 rows moved'")
      continue
    names = moved(base, got)
    if names is None:
      print(f"{mid} ?")
      continue
    print(f"{mid} moved {len(names)}: {' '.join(names) if names else '(NONE)'}")
    print(f"    {what}")

  # the control, once more, and the file is byte-identical to the pristine one
  open(target, "w").write(pristine)
  print()
  print(f"scratch tree restored: {open(target).read() == pristine}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
