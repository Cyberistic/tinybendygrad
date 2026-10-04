#!/usr/bin/env python3
"""c2d-fixture-identity.py -- IS `s5_copy_sel` ONE FIXTURE OR TWO?

THE QUESTION. `s5_copy_sel` is GREEN and both sides print `Ops.COPY/Ops.MSELECT Ops.RANGE`.
The brief says the port's fixture is one CPython REFUSES. If that is true and the row is green,
then the two sides are NOT describing the same node -- and the first thing to find out is
HOW they differ, because that difference is the defect.

THE THREE FIXTURES, all called:

  PORT  `ops.bend:7021`   `UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))`; `s5.arena()`
                          (`ops.bend:6112-6133`) index 4 is
                          `Node{OpsPARAM{}, Nil{}, AParam{s5.pa(2)}, TNone{}}` and
                          `ParamArg.of` (`ops.bend:1359`) has `device: None{}` (ops.py:34).

  ORACLE `ops-501-oracle.py:209` `multi.copy_to_device(("PYTHON","PYTHON"), 1)` where
                          `multi` is `ops-501-oracle.py:164`
                          `UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32, 4, device=(...)))`.

  TUPLE  the spelling CPython ACCEPTS for `arg is not None`: a node whose `.device` IS a
          tuple -- which the oracle has and the port's `s5.arena()` does not.

`ops-501-oracle.py:164` and `ops.bend:6117` differ in FOUR fields: the OP (`PARAM` against
`ALLOC`), the SLOT (`2` against `3`), the SIZE (`None` against `4`) and the DEVICE
(`None` against `("PYTHON","PYTHON")`). `sig()` prints the op name and the src op SEQUENCE,
so it cannot see any of the four: two nodes that differ in all four print the same sig.
That is the whole defect in one sentence, and it is MEASURED below by printing the sig of
each fixture rather than by asserting it.

    DEV=NULL python3 .agents/slop/c2d-fixture-identity.py
"""
import sys

sys.path.insert(0, ".")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp  # noqa: E402


def sig(u: UOp) -> str:
  """`ops-501-oracle.py:45`'s printer, transcribed so the sigs are comparable to the row."""
  return f"{u.op.name}/" + " ".join(s.op.name for s in u.src) + " "


def show(nm, fn):
  try:
    print(f"{nm} = ok | {fn()}")
  except BaseException as e:  # noqa: BLE001 -- an AssertionError IS the answer
    print(f"{nm} = RAISED {type(e).__name__}: {e}")


def main():
  # `s5.arena()` index 4 -- `s5.pa(2)` is `ParamArg.of(2, int32)` (ops.bend:6110).
  port4 = UOp(Ops.PARAM, src=(), arg=ParamArg(2, dtypes.int32))
  oracle_multi = UOp(Ops.ALLOC, src=(), arg=ParamArg(3, dtypes.int32, 4, device=("PYTHON", "PYTHON")))

  print(f"port_node4_op = {port4.op.name} oracle_multi_op = {oracle_multi.op.name}")
  print(f"port_node4_arg = {port4.arg!r}")
  print(f"oracle_multi_arg = {oracle_multi.arg!r}")
  print(f"port_node4_device = {port4.device!r} oracle_multi_device = {oracle_multi.device!r}")
  print(f"port_node4_size = {port4.arg.size!r} oracle_multi_size = {oracle_multi.arg.size!r}")
  print(f"port_node4_slot = {port4.arg.slot!r} oracle_multi_slot = {oracle_multi.arg.slot!r}")
  print(f"port_node4_src_n = {len(port4.src)} oracle_multi_src_n = {len(oracle_multi.src)}")

  # THE SIGS, side by side. This is the row: if these agree while the refusals disagree, then
  # `sig()` cannot see the device and the green row is a statement about two different nodes.
  show("sig_port_node4_alone", lambda: sig(port4))
  show("sig_oracle_multi_alone", lambda: sig(oracle_multi))

  # THE ROW, called on BOTH fixtures, exactly as `ops-501-oracle.py:209` and `ops.bend:7021`
  # spell it. ONE OF THESE TWO REFUSES. The row name is the same for both.
  show("row_name_s5_copy_sel PORT fixture", lambda: sig(port4.copy_to_device(("PYTHON", "PYTHON"), 1)))
  show("row_name_s5_copy_sel ORACLE fixture", lambda: sig(oracle_multi.copy_to_device(("PYTHON", "PYTHON"), 1)))

  # AND THE SHAPE THAT MAKES THE PORT'S ROW BUILDABLE AT ALL: a `PARAM` whose device IS a
  # tuple. Same op as the port's node 4, same slot, same `None` size -- ONLY the device
  # differs, so this pair isolates the assert to exactly one field.
  port4_tuple = UOp(Ops.PARAM, src=(), arg=ParamArg(2, dtypes.int32, None, None, None, None,
                                                     None, ("PYTHON", "PYTHON")))
  print(f"port_node4_tuple_arg = {port4_tuple.arg!r}")
  show("row_name_s5_copy_sel PARAM device tuple", lambda: sig(port4_tuple.copy_to_device(("PYTHON", "PYTHON"), 1)))
  show("row_name_s5_copy_sel PARAM device none arg none",
       lambda: sig(port4.copy_to_device(("PYTHON", "PYTHON"))))

  # THE OTHER HALF OF THE Ladder: `arg is None` SATISFIES the assert whatever the device is,
  # so `s5_copy_single`/`s5_copy_multi` (arg=None, ops.bend:7029-7030) are the positive
  # neighbours of `refuse_tuple_device_arg` on the PORT's own node 4.
  show("row_name_s5_copy_multi PORT node4 arg none", lambda: sig(port4.copy_to_device(("PYTHON", "PYTHON"))))
  show("row_name_s5_copy_single PORT node4 arg none", lambda: sig(port4.copy_to_device("PYTHON")))


if __name__ == "__main__":
  main()