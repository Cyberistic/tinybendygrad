#!/usr/bin/env python3
"""GAP 1, the `op` finding: does CPython's walk REFUSE `op=0` where the port's
`op` fixture spells `0`, and is that value reachable at all in the port?

DRIVER 1 -- CPython.  `_walk` is `__init__`'s own write loop (dsl.py:334-335),
and `FixedBitField.set` (dsl.py:120-123) opens `assert val is None`.
DRIVER 2 -- THE PORT, by reading `fld_encode.k`'s K_FIXED arm (dsl.bend:1287).
"""
import importlib.util, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
spec = importlib.util.spec_from_file_location(
    "_o", str(ROOT / "gates/amd_dsl_census-oracle.py"))
o = importlib.util.module_from_spec(spec)
spec.loader.exec_module(o)

for op_val in (None, 0, 5):
    vl = [("op", op_val), ("vdst", o._r(266)), ("src0", o._r(3)),
          ("src1", o._r(5)), ("op_sel", 2), ("sdst", o._r(8))]
    raw, msg = o._walk(o.VOP2_FIELDS, vl)
    print(f"CPython _walk op={op_val!r:>5}: word={o.hex8(raw)}  msg={msg!r}")

print()
print("the port's F64_FIELDS/op is Fld.fixed(...,5), its VOP2 op is "
      "Fld.fixed(...,0); both are K_FIXED and fld_encode.k case 1n returns")
print("Res{Fld.dflt(Vf.f(vf)), \"\"} -- `Ov.off(Vf.v(vf))` IS NOT READ.")
print("grep -n 'case 1n' dsl.bend:")
import re
src = (ROOT / "tinybendygrad/renderer/amd/dsl.bend").read_text()
for m in re.finditer(r"^.*case 1n:.*$", src, re.M):
    print("   ", m.group(0))
for m in re.finditer(r"^def fld_encode\.k.*?\n(?:  .*\n)+", src, re.M):
    print(m.group(0).rstrip())