#!/usr/bin/env python3
"""Reach probe for the four remaining ops: CUSTOM_FUNCTION MSELECT MSTACK STAGE.

Builds candidate graphs on the PY side and prints, per candidate: whether the target op
reaches the normal form, its node row, and the device names the stream carries (the oracle
REQUIRES py devnames == bend devnames, so a fixture with no ParamArg would fail SELFCHECK).
"""
from __future__ import annotations

import os
import sys

os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import graphcmp as G  # noqa: E402

G.load_tinygrad()
G.COMM = G.commutative()
from tinygrad import Tensor  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, UOp  # noqa: E402


def cand_custom_function():
  return UOp.custom_function("myfn", Tensor.empty(4, 3).uop)


def cand_mselect():
  return Tensor.empty(4, 3).uop.copy_to_device(("CPU", "CPU")).mselect(0)


def cand_mstack():
  a = Tensor.empty(4, 3).uop
  b = Tensor.empty(4, 3).uop
  return UOp(Ops.MSTACK, src=(a, b))


def cand_stage_eager():
  return (Tensor.empty(4, 3) + 1).contiguous().uop


def cand_stage_bufferize():
  return Tensor.empty(4, 3).uop.bufferize()


CANDS = {"custom_function": cand_custom_function, "mselect": cand_mselect,
         "mstack": cand_mstack, "stage_eager": cand_stage_eager,
         "stage_bufferize": cand_stage_bufferize}


def main() -> int:
  target = {"custom_function": "CUSTOM_FUNCTION", "mselect": "MSELECT",
            "mstack": "MSTACK", "stage_eager": "STAGE", "stage_bufferize": "STAGE"}
  for name, fn in CANDS.items():
    try:
      u = fn()
      rows = list(u.toposort())
      ops = [n.op.name for n in rows]
      hit = target[name] in ops
      wire = [G.row_of(n, i + 1, {id(m): i + 1 for i, m in enumerate(rows)})
              for i, n in enumerate(rows)]
      print(f"# {name}: rc=0 target={target[name]} reached={hit} nodes={len(rows)} "
            f"devs={sorted(G.devnames(wire))}")
      print(f"#   census: {' '.join(f'{o}={ops.count(o)}' for o in sorted(set(ops)))}")
      for i, n in enumerate(rows):
        if n.op.name == target[name]:
          print(f"#   ROW: {i + 1} {n.op.name} dtype={n.dtype.name} shape={G.cshape(n)} "
                f"arg={G.carg(n.op, n.arg)}")
    except Exception as e:  # noqa: BLE001
      print(f"# {name}: rc=1 EXC {type(e).__name__}: {e}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
