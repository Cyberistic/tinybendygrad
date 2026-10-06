#!/usr/bin/env python3
# fold-lift-mutate.py -- the mutation table for `_min_max`'s OP TABLE (ops.py:1105-1163).
#
# TWO RULES FROM agent-core.md, both measured rather than adopted:
#   * IT DIFFS WHOLE `name=value` LINES. A name-comparing harness reported 0 for all 30
#     mutations in one unit and 0 for all 68 in another.
#   * A `0` IS REPORTED AS A REQUEST FOR A FIXTURE, A THEOREM, OR AN UNFIXABLE. Never
#     closed with a row that encodes the equivalence as a check.
#
# The baseline is captured from the SAME file in the SAME state immediately before the
# first mutation, because `fold.bend` and `LAWS/spec.bend` both went transiently
# uncompilable from a concurrent agent during this unit and a stale baseline makes every
# row look like it moved.
import os
import subprocess
import sys
import time

WORK = 'tinybendygrad/uop/fold.bend'
BEND = './bin/bend'

# (label, old, new, what it is testing)
MUT = [
  ("L1", "def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:\n  match m:\n    case Some{x}: x\n    case None{}: fb",
   "def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:\n  match m:\n    case Some{x}: x\n    case None{}: fb\n",
   "SANITY: a no-op edit, expected to move 0. It is in the table on purpose: a harness that "
   "reports a row-move for a no-op is reporting the substrate, not the mutation"),
  ("L2", "def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:\n  match m:\n    case Some{x}: x\n    case None{}: fb",
   "def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:\n  match m:\n    case Some{x}: fb\n    case None{}: fb",
   "the FALL-THROUGH, inverted: a binary op with no arm would answer the dtype limits twice "
   "and one WITH an arm would answer them instead. `ft_cmpeq` is the row"),
  ("L3", "Bool.and(O.GroupOp.binary(op), dt_is.not_float(d))",
   "Bool.and(O.GroupOp.binary(op), dt_is.not_float(d))\n",
   "SANITY on the block GATE itself: an op outside `GroupOp.Binary` must never meet an arm"),
  ("L41", "def mm.lift.mv(+srcs: List<&2, Bnd2>) -> Bnd2: mm.s0(srcs)",
   "def mm.lift.mv(+srcs: List<&2, Bnd2>) -> Bnd2:\n  mm.src2(srcs, 0)",
   "the passthrough rewritten as a `src2` spelling of itself: the same answer, reached "
   "differently, so it is the control for L29's `src[1]`"),
  ("L42", "def bnd.same(a: Bool, b: Bool) -> Bool: Bool.not(Bool.xor(a, b))",
   "def bnd.same(a: Bool, b: Bool) -> Bool: Bool.xor(a, b)",
   "`Bool` equality is the NEGATION of exclusive-or and not the exclusive-or itself: the "
   "control that says the sign comparisons are reading a real equality"),
  ("L4", "Bool.and(O.GroupOp.binary(op), dt_is.not_float(d))",
   "Bool.or(O.GroupOp.binary(op), dt_is.not_float(d))",
   "the block is entered on a NON-BINARY op: `DEFINE`-family ops would meet the arms"),
  ("L40", "    case O.OpsALLOC{}: mm.defines(arg, d)",
   "    case O.OpsALLOC{}: mm.default(d)",
   "the `Defines` arm narrowed to PARAM and BUFFER: an ALLOC with a `vmin_vmax` would lose it, and `GroupOp.Defines` names all three"),
]


def run(extra=()):
  r = subprocess.run([BEND, WORK, *extra], capture_output=True, text=True)
  return r.stdout, (r.stdout + r.stderr).splitlines()[0] if (r.stdout + r.stderr).splitlines() else '<none>'


def rows():
  out = {}
  for line in run()[0].splitlines():
    if ' ' in line:
      k, v = line.split(' ', 1)
      out[k] = v
  return out


def main():
  src = open(WORK).read()
  base = rows()
  chk = run(('--check-only',))[1]
  if not base:
    print('BASELINE IS EMPTY -- refusing to run')
    return 1
  print(f'baseline: {len(base)} bend rows, {chk!r}')
  moved_total = 0
  for label, old, new, why in MUT:
    if src.count(old) != 1:
      print(f'{label:4s} SKIP -- pattern occurs {src.count(old)}x, not 1')
      continue
    open(WORK, 'w').write(src.replace(old, new))
    time.sleep(0.15)
    got = rows()
    chk = run(('--check-only',))[1]
    moved = sorted(k for k in base if base.get(k) != got.get(k))
    gone = sorted(k for k in base if k not in got)
    if gone:
      print(f'{label:4s} moved {len(moved) + len(gone):4d} (rows LOST: {len(gone)})  '
          f'{chk!r}')
      print(f'       lost: {gone[:4]}')
    else:
      print(f'{label:4s} moved {len(moved):4d}  {chk!r}  {moved[:6] if moved else ""}')
    moved_total += len(moved) + len(gone)
    open(WORK, 'w').write(src)
    time.sleep(0.1)
  open(WORK, 'w').write(src)
  print(f'\nfile restored byte-identical; {moved_total} row-moves over {len(MUT)} mutations')
  return 0


if __name__ == '__main__':
  sys.exit(main())