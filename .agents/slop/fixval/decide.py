#!/usr/bin/env python3
"""GAP 1, question 1: is 4660 vs 0x12345678 a BUG or a DELIBERATE fixture?

THE DECIDING MEASUREMENT.  `gates/amd_dsl_census-oracle.py:802-807` gives
`to_bytes_f64i` its reason for existing, and the reason is about the VALUE:

    "THE ONLY `to_bytes_*` ROW WITH A NONZERO HIGH BYTE ABOVE BYTE 0 ... Added
     because a mutation proved it missing: masking the port's `wbyte` high limb
     to eight bits moved ZERO rows and left the gate GREEN, because every other
     word in this census has a high limb of `0x00` or `0x48`.  `F64_FIELDS` is 64
     bits wide, `_base_size` is 8, and `F64_VALS`' `lit` is `0x12345678`, so all
     four high bytes are nonzero."

So the row's stated property is a CLAIM ABOUT THE FIXTURE.  Count the nonzero
bytes above byte 0 under each value: if the claim is false for 4660, then 4660
cannot be the value that row was written against.
"""
import importlib.util, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
spec = importlib.util.spec_from_file_location(
    "_o", str(ROOT / "gates/amd_dsl_census-oracle.py"))
o = importlib.util.module_from_spec(spec)
spec.loader.exec_module(o)

sz = o._base_size(o.F64_FIELDS)
print(f"F64_FIELDS hi/lo = {[(n, f.hi, f.lo) for n, f in o.F64_FIELDS]}  _base_size={sz}")
for lit in (4660, 0x1234, 0x12345678):
    raw, _ = o._walk(o.F64_FIELDS, [("op", None), ("lit", lit)])
    h = o._to_bytes_hex(raw, sz)
    hi_bytes = [h[2 * i:2 * i + 2] for i in range(4, sz)]
    print(f"lit={lit:#012x}  to_bytes={h}  bytes 4..7={hi_bytes}  "
          f"nonzero_above_byte0={sum(1 for b in hi_bytes if b != '00')}/4")

# and the OTHER two `to_bytes_*` rows' high limbs, which the row says are
# `0x00` or `0x48` -- so this one really is the only row that can see a
# high-limb masking mutation.
for nm, fl, vl in (("to_bytes_vop2", o.VOP2_FIELDS, o.VOP2_ALL),
                   ("to_bytes_f32i", o.F32_FIELDS, o.F32_VALS),
                   ("to_bytes_f16i", o.F16_FIELDS, o.F16_VALS)):
    s = o._base_size(fl)
    raw, _ = o._walk(fl, vl)
    h = o._to_bytes_hex(raw, s)
    print(f"{nm:<14} size={s}  to_bytes={h}  high limb={h[2 * (s - 2):]}")