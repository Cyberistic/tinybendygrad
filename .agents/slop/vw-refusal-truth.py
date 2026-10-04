#!/usr/bin/env python3
"""vw-refusal-truth.py -- WHAT CPython DOES AT `ops.py:759/761/763`, READ FROM THE SOURCE AND
THEN CALLED, PLUS THE FIXTURE `s5_copy_sel`'s ROW WAS ACTUALLY ABOUT.

WHAT THIS FILE IS FOR. The gate row `s5_copy_sel` was green at `Ops.COPY/Ops.MSELECT
Ops.RANGE` on a node CPython REFUSES, and a green row asserting agreement on a node that
raises is not a coverage gap -- it is a false statement. This file establishes what upstream
does, where, and by which MECHANISM, because the mechanism is observable and the oracle prints
it: a bare `assert` and a `raise` are different behaviours and a row that accepts either is
testing neither.

THE ANSWER, FROM THE SOURCE, with lines:

    tinygrad/uop/ops.py:758   def copy_to_device(self, device, arg=None):
    tinygrad/uop/ops.py:759     if is_disk_device(device):
    tinygrad/uop/ops.py:760       raise RuntimeError("COPY to DISK is not allowed; ...")
    tinygrad/uop/ops.py:761     assert arg is None or isinstance(self.device, tuple)
    tinygrad/uop/ops.py:762     inp = self if arg is None else UOp(Ops.MSELECT, src=(self,), arg=arg)
    tinygrad/uop/ops.py:763     if inp.dtype in dtypes.weaks: raise RuntimeError(f"cannot create storage for weak dtype {inp.dtype}")

`ops.py:761` IS A BARE `assert` -- NO MESSAGE. So its observable is `AssertionError` with an
EMPTY string, which is exactly what `show()` below prints as `RAISED AssertionError: ` with
nothing after the colon, and that is what the oracle lane records as the row VALUE. The other
two are `raise` statements and carry messages. FOUR refusals, not three, because:

    tinygrad/uop/ops.py:892     assert isinstance(self.src[0].device, tuple), \
                                  f"mselect must be on tuple device, getting {self.src[0].device}"

is a fourth, inside `UOp.device`'s MSELECT arm. It HAS a message where 761 has none, so it is
distinguishable from 761 by class AND by payload, and it fires LAZILY -- on the first
`.device` READ, not at construction. `UOp.mselect(1)` on the refused fixture below
CONSTRUCTS FINE and only the read raises. Two facts that a single row would have merged.

`ops.bend:6998` says "THE TWO `raise`s ARE NOT PORTED". That UNDER-COUNTS: there are two
`raise`s AND two `assert`s, and the assert on the port's own fixture is 761.

--------------------------------------------------------------------------------
THE FIXTURE, AND THE ROW THAT WAS WRONG ABOUT IT. Three claims about `s5.selrow`'s node 4
circulated; only one survives contact with the port and with CPython.

    WRONG: "node 4 is `ParamArg.of(2, int32)` with `device = None`". `ops.bend:7021` calls
    `UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))` and `s5.devrows` is handed
    `s5.ga.arena()` (`ops.bend:7095`) -- NOT `s5.arena()`. Run against the port:

        probe_ga_op_1=Ops.BUFFER  probe_ga_op_2=Ops.ALLOC  probe_ga_op_3=Ops.PARAM
        probe_ga_op_4=Ops.SHRINK   probe_ga_nsrc_4=1       probe_ga_src_4_0=Ops.BUFFER

    so node 4 is `Node{OpsSHRINK{}, [1], ATuple{Nil{}}}` (ops.bend:6435) -- a SHRINK over the
    BUFFER at node 1, with an `ATuple` arg and NOT an `AParam` at all. Both arenas have an
    index 4 and only one of them is the arena the call receives.

    RIGHT, and for a different reason: the assert STILL fires, because `UOp.device`
    (ops.py:887-899) has no SHRINK arm, so a SHRINK falls through to its last two lines --
    `for x in self.src: if x.device is not None: return x.device` then `return None` -- and
    the BUFFER at node 1 is `ParamArg(1, int32)` (`ops.bend:6432` via `s5.pa(1)`,
    ops.bend:6110) whose `device` default is `None` (ops.py:34). MEASURED below:
    `node4_device = None`. A `None` from the fall-through, not a `None` from a `ParamArg`
    field: same guard, different node, and a port that special-cases `AParam` would miss it.

    AND THE ORACLE'S FIXTURE WAS A THIRD THING. `s5_copy_sel`'s CPython side is
    `ops-501-oracle.py:209` on `multi` (`ops-501-oracle.py:164`), an `Ops.ALLOC` with
    `device=('PYTHON','PYTHON')`. That differs from the port's node in OP, SLOT, SIZE and
    DEVICE, and `sig()` (ops-501-oracle.py:45) prints the op and the src op SEQUENCE, so it
    can see NONE of the four: both sides answer `COPY/MSELECT RANGE` and the row is green
    while comparing an accepted node against a refused one. That is why the twelve
    `c2d_*` IDENTITY rows exist in `validate.bend` -- a signature cannot carry a fixture's
    identity, and a fixture identity is what was wrong.

THE BOUNDARIES ARE RE-DERIVED HERE, BY CALLING, NOT INHERITED FROM THE PREVIOUS DRAFT. Two
were wrong when first written and were caught only by calling: `dtypes.weakint in dtypes.weaks`
is `True`, and EVERY `UOp.range` is `weakint` -- so a RANGE cannot be the positive side of
ops.py:763 on any axis type, and a positive row written from belief is a positive row FOR a
refusal. `.agents/slop/vw-boundaries.py` is where the exhaustion lives; the three facts this
file depends on are re-measured here so this file stands alone:

    `dtypes.weaks` is a set of size 2 -- `weakint`, `weakfloat`
    `UOp.range(4, 0, at).dtype` is `weakint` for every `AxisType` member
    `arg=0` REFUSES on a scalar device, so ops.py:761 tests `is None` and NOT truth

    DEV=NULL python3 .agents/slop/vw-refusal-truth.py
"""
import sys

sys.path.insert(0, ".")

from tinygrad.device import is_disk_device  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, AxisType, ParamArg, UOp  # noqa: E402

SRC = "tinygrad/uop/ops.py"


def show(nm, fn):
  try:
    print(f"{nm} = ok | {fn()}")
  except BaseException as e:  # noqa: BLE001 -- an AssertionError IS the answer
    print(f"{nm} = RAISED {type(e).__name__}: {e}")


def source_line(n):
  with open(SRC) as f:
    return f.read().splitlines()[n - 1]


def main():
  # ---- 1. THE SOURCE, quoted, so the reading is checkable without running anything. -------
  for n in (758, 759, 760, 761, 762, 763, 892):
    print(f"ops.py:{n} | {source_line(n).strip()}")

  # ---- 2. THE FIXTURE `s5.selrow` CALLS, in the port's own shape. -----------------------
  # `s5.ga.arena()` node 1 is `s5.pa(1)` = `ParamArg.of(1, int32)` (ops.bend:6110, 6432) and
  # node 4 is a SHRINK over it (ops.bend:6435). `size` is left unset because `s5.pa` leaves
  # it unset; `ops-501-oracle.py:61` sets 9, and that difference is one of the four.
  buf = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32))
  shr = UOp(Ops.SHRINK, src=(buf,), arg=())
  print(f"node4_op = {shr.op.name} node4_arg = {shr.arg!r} node4_nsrc = {len(shr.src)}")
  print(f"node4_src0 = {shr.src[0].op.name} node1_arg = {buf.arg!r} node1_device = {buf.device!r}")
  print(f"node4_device = {shr.device!r} node4_device_is_tuple = {isinstance(shr.device, tuple)}")
  # THE NODE A BRIEF NAMED, at the index it named: `s5.ga.arena()` node 2 is `s5.pa(2)` =
  # `ParamArg(2, int32)`. It exists, its device is None, and it is NOT node 4.
  node2 = UOp(Ops.ALLOC, src=(), arg=ParamArg(2, dtypes.int32))
  print(f"node2_op = {node2.op.name} node2_arg = {node2.arg!r} node2_device = {node2.device!r}")
  # AND THE NODE THE ORACLE USED: `ops-501-oracle.py:164`'s `multi`.
  multi = UOp(Ops.ALLOC, src=(), arg=ParamArg(3, dtypes.int32, 4, device=("PYTHON", "PYTHON")))
  print(f"multi_op = {multi.op.name} multi_arg = {multi.arg!r} multi_device = {multi.device!r}")

  # ---- 3. THE REFUSAL, CALLED, ON ALL THREE FIXTURES. ------------------------------------
  show("s5_copy_sel PORT node4 SHRINK", lambda: repr(shr.copy_to_device(("PYTHON", "PYTHON"), 1)))
  show("s5_copy_sel ORACLE multi", lambda: repr(multi.copy_to_device(("PYTHON", "PYTHON"), 1)))
  show("s5_copy_sel BRIEF node2 ALLOC", lambda: repr(node2.copy_to_device(("PYTHON", "PYTHON"), 1)))
  # THE POSITIVE CONTROL one step away in `arg`, on the port's own node. `arg is None` is
  # satisfied by the `None` alone, so this BUILDS and the SHRINK's `None` device is harmless.
  show("s5_copy_multi PORT node4 arg none", lambda: repr(shr.copy_to_device(("PYTHON", "PYTHON"))))
  # AND `arg=0`, which REFUSES. This is the boundary the previous draft did not have: ops.py:761
  # is an IDENTITY test, so a falsy index is still an index, and a port guarding with "an empty
  # shard index means no shard" passes a row written with `arg=1` and fails this one.
  show("s5_copy_sel PORT node4 arg zero", lambda: repr(shr.copy_to_device(("PYTHON", "PYTHON"), 0)))

  # ---- 4. THE OTHER TWO REFUSALS, CALLED, WITH THEIR POSITIVE CONTROLS. -----------------
  show("refuse_disk", lambda: repr(buf.copy_to_device("DISK")))
  show("refuse_disk_tuple", lambda: repr(buf.copy_to_device(("DISK", "PYTHON"))))
  show("positive_scalar_cpu", lambda: repr(buf.copy_to_device("PYTHON")))
  # THE EXACT HEAD MATCH, and the case fold. `'NODISK'` and `'DISKX'` are on the POSITIVE side
  # of device.py:70's `d.split(":", 1)[0].upper() == "DISK"`, and `'disk'` is on the negative
  # side, so a substring test or a case-sensitive one is caught by the pair.
  show("positive_disk_nodisk", lambda: repr(buf.copy_to_device("NODISK")))
  show("positive_disk_diskx", lambda: repr(buf.copy_to_device("DISKX")))
  show("refuse_disk_lower", lambda: repr(buf.copy_to_device("disk")))

  show("refuse_weakint", lambda: repr(UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.weakint)).copy_to_device("PYTHON")))
  show("refuse_weakfloat", lambda: repr(UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.weakfloat)).copy_to_device("PYTHON")))
  show("positive_i32", lambda: repr(UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32)).copy_to_device("PYTHON")))
  show("positive_f32", lambda: repr(UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.float32)).copy_to_device("PYTHON")))
  # A RANGE IS NOT A POSITIVE 763 FIXTURE, and this is why. EVERY `UOp.range` is `weakint`,
  # over EVERY `AxisType` member -- measured over all of them, not over the one that was tried
  # first. A range-based positive row is a positive row for a refusal, and it is green.
  for at in AxisType:
    show(f"refuse_range_{at.name}", lambda at=at: repr(UOp.range(4, 0, at).copy_to_device("PYTHON")))

  # ---- 5. THE BOUNDARIES, RE-MEASURED. --------------------------------------------------
  print(f"n_weaks = {len(dtypes.weaks)} weaks = {[str(d) for d in dtypes.weaks]}")
  print(f"weakint_in_weaks = {dtypes.weakint in dtypes.weaks} "
        f"weakfloat_in_weaks = {dtypes.weakfloat in dtypes.weaks}")
  print(f"range_dtypes = {sorted({str(UOp.range(4, 0, at).dtype) for at in AxisType})} "
        f"n_axis_types = {len(list(AxisType))}")
  print(f"is_disk_device('disk') = {is_disk_device('disk')} "
        f"is_disk_device('NODISK') = {is_disk_device('NODISK')}")

  # ---- 6. THE FOURTH REFUSAL, ops.py:892, AND ITS LAZINESS. -----------------------------
  # `UOp.mselect(self, arg)` -- ops.py:769 -- CONSTRUCTS on the refused fixture. The assert
  # lives in `UOp.device`'s MSELECT arm and fires on the first READ. Two calls, two answers,
  # and merging them into one row would hide that the refusal is LAZY -- the same shape of
  # error `validate-oracle.py` records for `dv_bad_dtype_bitcast`.
  show("mselect_construct", lambda: repr(shr.mselect(1)))
  show("mselect_device_read", lambda: repr(shr.mselect(1).device))


if __name__ == "__main__":
  main()