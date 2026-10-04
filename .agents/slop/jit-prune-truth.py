#!/usr/bin/env python3
"""jit-prune-truth.py -- the CPython side of `engine/jit.bend`'s `prune_*` rows, CALLED.

`jit-oracle.py` wires the whole file and SKIPS four rows (msg_dtype_mismatch,
info_repr_flat, msg_captured, msg_pruned) -- so `prune_sig_kept` and `prune_sig_once` are
PORT-ONLY ROWS with no oracle on either side. Two ports agreeing about nothing is what
`rebase-gate.py` was written to distinguish from success, and here it applies to a single
row: `prune_sig_kept=n=1 op=Ops.LINEAR nsrc=1 srcops=Ops.NOOP` asserts that the kept
linear's source reads as a NOOP, and nothing ever checked that against CPython.

So this file CALLS `tinygrad.engine.jit.prune_linear` (jit.py:14) on the SAME fixture
`fx_make` builds (jit.bend:1214) and prints the four facts in the port's `j_sig` format.

THE POINT OF THE ROW. `prune_linear` returns `linear.replace(src=tuple(kept))`. jit.py:19
appends `si` -- the NODE. jit.bend:765 appends the literal `0`. Index 0 is this port's
arena bottom (`Arena.empty`, ops.bend:1166), so the kept linear's source reads back as
`Node{OpsNOOP{}, ...}`. That is exactly the signature the arena-aliasing defect class
prints, produced here by a WRONG CONSTANT rather than a wrong arena -- and it is
INVISIBLE to the whole file because the row that would show it has no oracle.

Run: `.venv/bin/python .agents/slop/jit-prune-truth.py`
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.engine.jit import prune_linear
from tinygrad.uop.ops import ProgramInfo


def fx_make():
  """engine/jit.bend:1214 `fx_make`, node for node.

  `f0` is the port's explicit NOOP and has NO CPython counterpart -- CPython's `None` UOp
  is spelled `UOp(Ops.NOOP)`, which is what `f0` is, so this IS faithful and the NOOP in the
  answer is CPython's own rather than the port's sentinel. The row is therefore a fair
  comparison, not a spelling mismatch."""
  f0 = UOp(Ops.NOOP)
  f1 = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float))
  f2 = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.float))
  f3 = UOp(Ops.BUFFER, arg=ParamArg(2, dtypes.float))
  f4 = UOp(Ops.PROGRAM, arg=ProgramInfo((1, 1, 1), (1, 1, 1), (), (), (f1,), (f2,)))
  f5 = UOp(Ops.CALL, src=(f4, f1, f2))
  f6 = UOp(Ops.UNSHARD, src=(f1,))
  f7 = UOp(Ops.LINEAR, src=(f5, f2))
  return f7


def sig(u):
  """the port's `j_sig` (jit.bend:795) format, SPELLING MATCHED TO THE PORT.

  `n= op= nsrc= srcops=` with bare `Ops.NAME`, not `UOp(Ops.NAME)`. The first version of
  this oracle printed CPython's own repr and the differ then reported DISAGREE on every row
  after the fix -- with the two values character-for-character the same op sequence. That is
  the `nv_query_litter` failure in a new costume: a disagreement manufactured by the
  COMPARISON, not by either side. A row format is a contract; this file honours the port's.
  """
  return (f"n={len(u.src)} op=Ops.{u.op.name} nsrc={len(u.src)} "
          f"srcops={'|'.join('Ops.' + s.op.name for s in u.src)}")


def main():
  lin = fx_make()
  b1 = lin.src[1]
  # `needed=[b1]` and `sibufs_of=[[b1], Nil]` are the two ARGUMENTS of the two rows
  # (jit.bend:1527-1528), not an accident of the fixture.
  kept, onetime = prune_linear(lin, {b1})
  print(f"prune_sig_kept={sig(kept)}")
  print(f"prune_sig_once={sig(onetime)}")
  # the raw node identities, so a reader can see WHICH node the port would need
  print(f"kept_src_ops={[s.op.name for s in kept.src]}")
  print(f"once_src_ops={[s.op.name for s in onetime.src]}")
  print(f"needed_is_b1={b1.op.name}")


if __name__ == "__main__":
  main()