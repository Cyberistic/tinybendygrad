#!/usr/bin/env python3
"""vw-boundaries.py -- EVERY BOUNDARY OF `copy_to_device`, RE-DERIVED BY CALLING.

WHY THIS FILE EXISTS. `vw-refusal-truth.py` had two boundaries wrong when first written and
was caught only by calling: `dtypes.weakint in dtypes.weaks` is `True`, and every
`UOp.range` is `weakint` whatever `AxisType` it is given. So a positive row written from
belief is a positive row FOR A REFUSAL, and it is green. This file does not inherit a
boundary; it EXHAUSTS the finite sets the boundaries are drawn across and prints the
membership, so a boundary is a measured edge of an enumerated set rather than a belief.

THE THREE REFUSALS, and the set each boundary is drawn across:

    ops.py:759  `is_disk_device(device)`      -- device.py:69-70, over NAME STRINGS
    ops.py:761  `assert arg is None or isinstance(self.device, tuple)`
    ops.py:763  `if inp.dtype in dtypes.weaks: raise RuntimeError(...)`

WHAT "EXHAUSTED" MEANS HERE, so the word is not doing unearned work:

  * `dtypes.weaks` -- ENUMERATED over every member of `dtypes`, and the membership printed
    per dtype. `len(dtypes.weaks)` is printed beside it. A boundary drawn across a set of
    size TWO with a positive row for `int32` is one measurement; it is two if the negative
    side is walked in full, because `float32`, `uint32`, `half` and every other member are
    then also shown to be on the POSITIVE side of the line.
  * `is_disk_device` -- the device-name boundary is over strings, and strings are not
    finite, so what is exhausted here is the SPELLING AXIS that can move the answer:
    case (`disk`/`DISK`/`Disk`), the `:`-SUFFIX (`DISK:0`/`DISK:0:1`), and the position of
    the DISK entry in a tuple (first, last, middle). Every row is CALLED.
  * the 761 assert -- a FOUR-QUADRANT table over `(arg is None) x (device is a tuple)`, and
    the quadrant table IS the boundary: two of the four refuse and two do not, so no
    spelling of the guard that ignores either coordinate can be green on all four.

    ⚠ AND THE `arg is None` COORDINATE IS AN IDENTITY TEST, NOT A TRUTH TEST. `arg=0` is
    falsy and `arg` is `None` only when it is `None`, so `arg=0` with a scalar device
    REFUSES while a guard written as `if not arg` would build it. `arg_0_*` is the row, and
    it is the row a `Maybe<&2, U32>` port can most easily get wrong by testing the payload.

    DEV=NULL python3 .agents/slop/vw-boundaries.py
"""
import sys

sys.path.insert(0, ".")

from tinygrad.device import is_disk_device  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, AxisType, ParamArg, UOp  # noqa: E402


def out(nm, v):
  print(f"{nm}={v}")


def verdict(fn):
  """`ok` / `RAISED <Class>: <message>` -- the SAME vocabulary `vw-refusal-truth.py` uses, so a
  boundary row here and a fixture row there are comparable strings."""
  try:
    fn()
    return "ok"
  except BaseException as e:  # noqa: BLE001 -- the exception class IS the answer
    return f"RAISED {type(e).__name__}: {e}"


def sig(u):
  return f"{u.op.name}/" + " ".join(s.op.name for s in u.src)


def main():
  # ---------------------------------------------------------------- 1. `dtypes.weaks`, ENUMERATED.
  # Every member of `dtypes` is asked whether it is in `weaks`, so the boundary is the two
  # sides of a MEASURED partition and not "the two dtypes somebody remembered".
  # THE ENUMERATION, taken from `tinygrad/dtype.py:161` rather than from `dir()`, because
  # `dir(dtypes)` also lists ALIASES (`half`, `float16`, `int`, `i32`, ...) and enumerating
  # aliases measures the same dtype under four names. `dtypes.all` is `floats + ints +
  # (bool,)` -- 17 members -- and it does NOT contain `weaks`, so the enumeration adds
  # `weaks` plus `void` and `char`, or the boundary would be drawn across a set that
  # excludes two of the members the guard tests.
  uniq = []
  for d in tuple(dtypes.all) + tuple(dtypes.weaks) + (dtypes.void, dtypes.char):
    if all(str(d) != str(u) for u in uniq):
      uniq.append(d)
  uniq.sort(key=str)
  out("dt_all_n", len(uniq))
  for d in uniq:
    out(f"dt_in_weaks {d}", int(d in dtypes.weaks))
  out("dt_weaks_n", len(dtypes.weaks))
  out("dt_weaks", ",".join(str(d) for d in dtypes.weaks))
  # THE TWO CLAIMS THE PRIOR FILE GOT WRONG, re-derived rather than repeated.
  out("claim_weakint_in_weaks", int(dtypes.weakint in dtypes.weaks))
  out("claim_weakfloat_in_weaks", int(dtypes.weakfloat in dtypes.weaks))
  rng_dts = {}
  # `AxisType`'s MEMBERS, taken from the enum rather than from a hand-written list, so a new
  # axis type cannot fall outside the enumeration unnoticed. MEASURED to be eight.
  out("axis_types_n", len(list(AxisType)))
  for at in AxisType:
    try:
      rng_dts[at.name] = str(UOp.range(4, 0, at).dtype)
    except Exception as e:  # noqa: BLE001
      rng_dts[at.name] = f"RAISED {type(e).__name__}"
  for k, v in rng_dts.items():
    out(f"range_dtype {k}", v)
  # THE CLAIM UNDER TEST: "every `UOp.range` is weakint". A claim about a function needs its
  # DOMAIN, so the count of distinct dtypes over the enumerated axis types is printed beside
  # it: `1` is the claim holding over all eight, `2` is it failing somewhere.
  out("range_dtype_all_weakint", int(all(v == str(dtypes.weakint) for v in rng_dts.values())))
  out("range_dtype_distinct_n", len(set(rng_dts.values())))
  out("range_dtype_distinct", ",".join(sorted(set(rng_dts.values()))))

  # ---------------------------------------------------------------- 2. `is_disk_device`, CALLED.
  # device.py:69-70 over NAME STRINGS. Each is asked twice -- once directly, and once as the
  # `device` argument of a live `copy_to_device`, because the def and its ONE caller are two
  # different claims and a caller can be reached with a spelling the def is never called with.
  buf = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32))
  DEVS = ["CPU", "PYTHON", "DISK", "disk", "Disk", "dIsK", "DISK:0", "DISK:0:1", "DISK:",
          "CPU:1", "NODISK", "NDISK", "XDISK", "PYTHON:0", "", "DISKX", "0DISK"]
  TUPLES = [("DISK",), ("DISK", "CPU"), ("CPU", "DISK"), ("CPU", "DISK", "PYTHON"),
            ("PYTHON", "PYTHON"), ("disk", "CPU"), ("DISK:0", "CPU"), (), ("NDISK",),
            ("CPU",)]
  for d in DEVS:
    out(f"is_disk str {d!r}", int(is_disk_device(d)))
    out(f"c2d_disk_str {d!r}", verdict(lambda d=d: buf.copy_to_device(d)))
  for t in TUPLES:
    out(f"is_disk tuple {t}", int(is_disk_device(t)))
    out(f"c2d_disk_tuple {t}", verdict(lambda t=t: buf.copy_to_device(t)))

  # ---------------------------------------------------------------- 3. the 761 ASSERT, 4 QUADRANTS.
  # (arg is None) x (isinstance(self.device, tuple)). `scalar` has `device=None`,
  # `tupled` has `device=('CPU','METAL')`, and the two spellings of `arg` are `None`, `0` and
  # `1` so the identity test and a truth test are separated.
  scalar = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32))
  tupled = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.int32, None, None, None, None,
                                                None, ("CPU", "METAL")))
  for dn, node in (("scalardev", scalar), ("tupledev", tupled)):
    out(f"dev_is_tuple {dn}", int(isinstance(node.device, tuple)))
    out(f"dev_value {dn}", repr(node.device))
    for an, a in (("none", None), ("zero", 0), ("one", 1), ("neg1", -1)):
      out(f"assert_q {dn} arg{an}",
          verdict(lambda a=a, node=node: node.copy_to_device(("CPU", "METAL"), a)))

  # ---------------------------------------------------------------- 4. the 763 REFUSAL, per DTYPE.
  # One op, one arity, one device, and the dtype is the ONLY thing that moves. Every dtype is
  # asked, so the positive side of the boundary is as wide as the dtype table rather than one
  # remembered member.
  for d in uniq:
    u = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, d))
    out(f"c2d_dtype {d}", verdict(lambda u=u: u.copy_to_device("CPU")))
  # AND the same question through the MSELECT branch (`arg is not None`), because 763 reads
  # `inp.dtype` and `inp` is the MSELECT when `arg` is given -- so a weak dtype that only
  # refuses on one of the two branches is a boundary nobody has drawn.
  for d in (dtypes.int32, dtypes.weakint, dtypes.weakfloat):
    ut = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, d, None, None, None, None, None, ("CPU", "METAL")))
    out(f"c2d_dtype_mselect {d}", verdict(lambda ut=ut: ut.copy_to_device(("CPU", "METAL"), 1)))

  # ---------------------------------------------------------------- 5. WHAT IS ACTUALLY PORTED.
  # `UOp.device` (ops.py:887-899) is the thing 761 READS, so the port needs it, and its
  # reachability is what decides whether the guard is one line or a port. `MSELECT` has its
  # OWN assert (ops.py:892) with a DIFFERENT message, so a port that only reads
  # `self.device` at 761 and not at 892 is missing a second refusal.
  shr = UOp(Ops.SHRINK, src=(scalar,), arg=())
  print(f"device_of_shrink = {shr.device!r}")
  print(f"device_of_shrink_is_tuple = {isinstance(shr.device, tuple)}")
  print(f"mselect_own_assert = {verdict(lambda: shr.mselect(1))}")
  print(f"mselect_then_device = {verdict(lambda: shr.mselect(1).device)}")
  print(f"copy_to_device_source_is_assert_761 = "
        f"{'assert arg is None or isinstance(self.device, tuple)' in open('tinygrad/uop/ops.py').read()}")


if __name__ == "__main__":
  main()