#!/usr/bin/env python3
"""kn-noop-truth.py -- the `ops` row of codegen/kernel.bend, MEASURED, by walking the
fixture's own UOp objects.

WHY THIS FILE EXISTS. `kn-truth.py:167` prints the `ops` row as a HARDCODED LITERAL:

    print("ops=NOOP CONST CONST CONST SPECIAL BUFFER ... PROGRAM ")

and the port's row reads `NOOP CONST CONST CONST SPECIAL BUFFER ... PROGRAM`. So the row
AGREES, and the agreement is worthless: an oracle that states its own expected value is not
an oracle, and a dtype rename or a stale arena on the first index would move the PORT and
leave the ORACLE exactly where it was -- "0 disagreements" over an error made twice.

So this file DERIVES the row. It builds the SAME 19-node fixture as `kn_fixture`
(kernel.bend:998) with real `UOp(...)` constructors, records the op name of each node in
interning order, and prints `name=op1 op2 ... op19` with NOOP first -- because the fixture's
index list `ix` STARTS AT 0, and index 0 is this port's arena bottom, which stands in for
CPython's `None` UOp. CPython has no node 0, so the leading NOOP is the PORT's spelling and
this oracle asserts it is the SPELLING and not a reading.

Every row is printed from a value CPython computed. Nothing is typed.
"""
import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")

from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg
from tinygrad.dtype import dtypes

def fixture():
  """kernel.bend:998 `kn_fixture`, node for node.

  The BUFFER/PARAM args are `ParamArg`s with a slot and no dtype, matching `pa1`; the port
  reads the slot with `u32_none()` (dtype=None) which is ParamArg's own default here."""
  c0 = UOp(Ops.CONST, arg=0)
  c1 = UOp(Ops.CONST, arg=1)
  c4 = UOp(Ops.CONST, arg=4)
  sp = UOp.special(c4, "0")
  b7 = UOp(Ops.BUFFER, src=(sp,), arg=ParamArg(7, None))
  b3 = UOp(Ops.BUFFER, src=(sp,), arg=ParamArg(3, None))
  prm = UOp(Ops.PARAM, src=(sp,), arg=ParamArg(0, None))
  ru = UOp(Ops.RANGE, src=(c4, UOp(Ops.CONST, arg=0)), arg=AxisType.UPCAST)
  rl = UOp(Ops.RANGE, src=(c4, UOp(Ops.CONST, arg=1)), arg=AxisType.LOOP)
  sq1 = UOp(Ops.SQRT, src=(c0,))
  st1 = UOp(Ops.STORE, src=(c0, c1))
  al1 = UOp(Ops.ALLOC, src=(c1,))
  rd1 = UOp(Ops.REDUCE, src=(sq1, ru), arg=(Ops.ADD, 1))
  sk1 = UOp(Ops.SINK, src=(sq1,))
  pr1 = UOp(Ops.PROGRAM, src=(sk1,))
  pr2 = UOp(Ops.PROGRAM, src=(sk1, st1))
  ins0 = UOp(Ops.INS, src=())
  pr3 = UOp(Ops.PROGRAM, src=(sk1, ins0))
  pr4 = UOp(Ops.PROGRAM, src=(sk1, st1, c1))
  return [c0, c1, c4, sp, b7, b3, prm, ru, rl, sq1, st1, al1, rd1, sk1, pr1, pr2, ins0, pr3, pr4]

def main():
  nodes = fixture()
  ops = [n.op.name for n in nodes]
  # the port's `ix` is `[0] ++ [Found.i(each)]`, so `k_ops` prints index 0 -- the arena
  # bottom -- FIRST and then one op per minted node.  The leading NOOP is the PORT's
  # spelling of "no node"; CPython has no such object, so it is printed as the literal the
  # port must match and is NOT evidence of a read.
  print("ops=NOOP " + " ".join(ops) + " ")
  # the same row without the sentinel, so a reader can diff the 19 measured ops alone
  print("ops_nosentinel=" + " ".join(ops) + " ")
  print(f"n_nodes={len(nodes)}")

if __name__ == "__main__":
  main()