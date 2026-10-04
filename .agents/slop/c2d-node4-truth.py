#!/usr/bin/env python3
"""c2d-node4-truth.py -- `s5.selrow`'s NODE 4 IS A `SHRINK`, NOT A `ParamArg`.

THE BRIEF'S PREMISE, quoted: "node 4 is `ParamArg.of(2, int32)` with `device = None`".
MEASURED FALSE, and the way it is false matters, because the refusal survives while the
REASON does not.

`ops.bend:7021` calls `UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))` and `s5.devrows` is
handed `s5.ga.arena()` (`ops.bend:7095`) -- NOT `s5.arena()`. Measured by running the port:

    probe_ga_op_1=Ops.BUFFER   probe_ga_op_2=Ops.ALLOC   probe_ga_op_3=Ops.PARAM
    probe_ga_op_4=Ops.SHRINK    probe_ga_nsrc_4=1        probe_ga_src_4_0=Ops.BUFFER

So the node is `Node{OpsSHRINK{}, [1], ATuple{Nil{}}, TNone{}}` (`ops.bend:6435`) -- a SHRINK
over the BUFFER at node 1, and its `arg` is `ATuple{Nil{}}`, not an `AParam` at all. The
brief read `s5.arena()` (40 nodes, index 4 = ALLOC) where the call receives `s5.ga.arena()`
(29 nodes, index 4 = SHRINK); both arenas have an index 4 and only one is the arena the
call is given.

WHY THE REFUSAL STILL HAPPENS, AND WHY THAT IS NOT THE SAME CLAIM. `UOp.device`
(ops.py:887-899) has no SHRINK arm, so a SHRINK falls through to its LAST two lines --
`for x in self.src: if x.device is not None: return x.device` then `return None`. The
BUFFER at node 1 is `ParamArg(1, dtypes.int32)` (`ops.bend:6432` via `s5.pa(1)`,
ops.bend:6110), whose `device` default is `None` (ops.py:34), so `isinstance(self.device,
tuple)` is False at ops.py:761 with `arg=1`. The ASSERT FIRES -- but it fires on a
`None`-from-fall-through, not on a `None`-from-a-ParamArg-field. Different node, same guard.

THE ROW THIS PUTS A HOLE IN. `s5_copy_sel` is GREEN at
`Ops.COPY/Ops.MSELECT Ops.RANGE`. Its oracle side (`ops-501-oracle.py:209`) uses `multi`
(`ops-501-oracle.py:164`), an `Ops.ALLOC` with `device=('PYTHON','PYTHON')` -- a node the
port's fixture is NOT, in op, in slot, in size AND in device. `sig()` (ops-501-oracle.py:45)
prints the op and the src op SEQUENCE, so of those four differences it can see NONE:
both answer `COPY/MSELECT RANGE`. So the row compares an ACCEPTED node against a REFUSED
one and reports agreement, and the disagreement is invisible to the row's own printer.

    DEV=NULL python3 .agents/slop/c2d-node4-truth.py
"""
import sys

sys.path.insert(0, ".")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp  # noqa: E402


def show(nm, fn):
  try:
    print(f"{nm} = ok | {fn()}")
  except BaseException as e:  # noqa: BLE001 -- an AssertionError IS the answer
    print(f"{nm} = RAISED {type(e).__name__}: {e}")


def main():
  # `s5.pa(1)` -- ops.bend:6110 -- `ParamArg.of(1, int32)`, so `size=None` and `device=None`.
  # `s5.ga.arena()`'s node 1. `ops-501-oracle.py:61` gives this one `size=9` instead; printed
  # here so the size difference is a MEASUREMENT and not an accusation.
  buf_port = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32))
  buf_oracle = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32, 9))
  # node 4 -- ops.bend:6435 -- `Node{OpsSHRINK{}, [1], ATuple{Nil{}}, TNone{}}`.
  shrink4 = UOp(Ops.SHRINK, src=(buf_port,), arg=())
  shrink4_size9 = UOp(Ops.SHRINK, src=(buf_oracle,), arg=())

  print(f"node4_op = {shrink4.op.name} node4_arg = {shrink4.arg!r}")
  print(f"node4_nsrc = {len(shrink4.src)} node4_src0 = {shrink4.src[0].op.name}")
  print(f"node1_arg = {buf_port.arg!r} node1_oracle_arg = {buf_oracle.arg!r}")
  print(f"node1_device = {buf_port.device!r}")
  # `UOp.device` ON THE SHRINK -- the fall-through, read out rather than argued about.
  print(f"node4_device = {shrink4.device!r} node4_device_is_tuple = {isinstance(shrink4.device, tuple)}")
  # The node the brief NAMED, at a different index: node 2 is `s5.pa(2)` =
  # `ParamArg(2, int32)` (ops.bend:6433), and its device is None by the BUFFER/ALLOC arm
  # (ops.py:897) rather than by the fall-through.
  alloc2 = UOp(Ops.ALLOC, src=(), arg=ParamArg(2, dtypes.int32))
  print(f"node2_op = {alloc2.op.name} node2_arg = {alloc2.arg!r} node2_device = {alloc2.device!r}")

  # THE REFUSAL, called. Both spellings of node 4 -- the port's `size=None` and the
  # oracle's `size=9` -- so the refusal cannot be an artefact of the size difference.
  show("s5_copy_sel PORT node4 SHRINK size none", lambda: shrink4.copy_to_device(("PYTHON", "PYTHON"), 1))
  show("s5_copy_sel PORT node4 SHRINK size 9", lambda: shrink4_size9.copy_to_device(("PYTHON", "PYTHON"), 1))
  # THE POSITIVE CONTROL one step away: the SAME node, `arg=None`. `arg is None or ...` is
  # satisfied by the `None` alone, so this builds and the SHRINK's `None` device is fine.
  show("s5_copy_multi PORT node4 SHRINK arg none", lambda: shrink4.copy_to_device(("PYTHON", "PYTHON")))
  show("s5_copy_single PORT node4 SHRINK scalar arg none", lambda: shrink4.copy_to_device("PYTHON"))
  # AND the other step: the SAME node over a BUFFER with a TUPLE device, which is what
  # makes `s5_copy_sel`'s oracle fixture acceptable.
  buf_tuple = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32, None, None, None, None,
                                                    None, ("PYTHON", "PYTHON")))
  shrink_tuple = UOp(Ops.SHRINK, src=(buf_tuple,), arg=())
  print(f"shr_tuple_device = {shrink_tuple.device!r}")
  show("s5_copy_sel SHRINK tuple device arg 1", lambda: shrink_tuple.copy_to_device(("PYTHON", "PYTHON"), 1))
  # AND `Ops.MSELECT`'s OWN assert (ops.py:892), a DIFFERENT message, one step later.
  # `shrink4.mselect(1)` is what ops.py:762 would build if 761 did not fire first.
  show("mselect_of_node4_direct", lambda: repr(shrink4.mselect(1)))


if __name__ == "__main__":
  main()