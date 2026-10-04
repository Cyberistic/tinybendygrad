#!/usr/bin/env python3
"""vw-refusal-truth.py -- `copy_to_device`'s REFUSALS, CALLED. The requirement `uop/ops.bend`
needs before it can close them, stated as fixtures rather than as prose.

WHY NEGATIVE ROWS FIRST. `copy_to_device` (ops.py:758-765) has THREE refusals and the port
implements none of them:

    759  if is_disk_device(device):            -> RuntimeError("COPY to DISK is not allowed; ...")
    761  assert arg is None or isinstance(self.device, tuple)
    763  if inp.dtype in dtypes.weaks:         -> RuntimeError("cannot create storage for weak dtype ...")

The port's own comment (`ops.bend:6983`) says "THE TWO `raise`s ARE NOT PORTED", which
UNDER-COUNTS: there are two raises AND one assert, and the assert is the one the port's own
fixture trips. `s5.selrow` calls `UOp.copy_to_device(ar, 4, Some{1}, ...)` -- `arg=Some{1}` on
`s5.arena`'s node 4, which is `ParamArg.of(2, int32)` with `device=None`. CPython would REFUSE
that. MEASURED here as `refuse_tuple_device_arg`.

So the port cannot simply add the guards: a refusal is a RAISE, and `UOp.copy_to_device`
returns `Found`, not a sum. Closing the guards changes the return type, which is a different
port than the one that adds a `Bool`. What comes first is a set of fixtures that MUST FAIL,
each with CPython's own outcome attached -- a negative row per refusal, plus the POSITIVE
control that must keep building the node, because a guard that refuses everything is green on
every negative row and wrong on the only row that matters.

    DEV=NULL python3 .agents/slop/vw-refusal-truth.py
"""
import sys

sys.path.insert(0, ".")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp, AxisType  # noqa: E402


def show(nm, fn):
  try:
    print(f"{nm} = ok | {fn()}")
  except BaseException as e:  # noqa: BLE001 -- an AssertionError IS the answer
    print(f"{nm} = RAISED {type(e).__name__}: {e}")


def main():
  # THE POSITIVE CONTROL. A scalar PARAM copied to one device, `arg=None`: ops.py:761's assert
  # is satisfied by `None` and the node is built. Without this row every negative row below is
  # satisfied by a guard that refuses unconditionally.
  scalar = UOp(Ops.PARAM, (), ParamArg(2, dtypes.int32))
  show("positive_scalar_cpu", lambda: repr(scalar.copy_to_device("CPU")))

  # ops.py:759 -- a DISK device.
  show("refuse_disk", lambda: repr(scalar.copy_to_device("DISK")))
  # and the tuple form of the same device, because `is_disk_device` takes `str|tuple` and a
  # guard that only tests the scalar spelling refuses nothing on the tuple spelling
  show("refuse_disk_tuple", lambda: repr(scalar.copy_to_device(("DISK", "CPU"))))

  # ops.py:761 -- `arg is None or isinstance(self.device, tuple)`. The port's OWN `s5.selrow`
  # fixture is this shape: a scalar-device node with a shard index.
  show("refuse_tuple_device_arg", lambda: repr(scalar.copy_to_device(("CPU", "METAL"), arg=1)))
  show("positive_tuple_device_arg",
       lambda: repr(UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32, device=("CPU", "METAL")))
                    .copy_to_device(("CPU", "METAL"), arg=1)))

  # ops.py:763 -- a WEAK dtype input. BOTH members of `dtypes.weaks` (`weakint`, `weakfloat`)
  # and nothing else, so the boundary is a dtype NOT in that set of size TWO.
  show("refuse_weak_dtype", lambda: repr(UOp.range(4, 0, AxisType.WEAK).copy_to_device("CPU")))
  show("refuse_weakfloat_dtype",
       lambda: repr(UOp.range(4, 0, AxisType.WEAK, dtype=dtypes.weakfloat).copy_to_device("CPU")))
  # THE 763 BOUNDARY, two rows ONE STEP APART: the same op, the same arity, dtypes on either
  # side of `dtypes.weaks`. MEASURED, and the first draft of this file got it wrong twice --
  # `dtypes.weakint in dtypes.weaks` is TRUE, and EVERY `UOp.range` is `weakint`, so a RANGE
  # cannot be the positive side whatever axis it is given. A positive row written from the
  # belief rather than the call is a POSITIVE ROW FOR A REFUSAL, and it is green.
  show("positive_763_boundary",
       lambda: repr(UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32)).copy_to_device("CPU")))
  show("refuse_763_boundary",
       lambda: repr(UOp(Ops.BUFFER, (), ParamArg(1, dtypes.weakint)).copy_to_device("CPU")))
  print(f"dtypes_weaks = {[str(d) for d in dtypes.weaks]}")

  # WHAT `s5.selrow`'s NODE 4 IS, so the claim above is a measurement and not a reading of the
  # fixture table. `s5.pa(slot) = ParamArg.of(slot, int32)`, and `ParamArg.of`'s device default
  # is `None` (ops.bend:1368), so the port's node 4 has a scalar device.
  print(f"s5_node4_arg = {scalar.arg!r} device_is_tuple = {isinstance(scalar.device, tuple)}")
  print(f"n_weaks = {len(dtypes.weaks)} weakint_in_weaks = {dtypes.weakint in dtypes.weaks}")


if __name__ == "__main__":
  main()