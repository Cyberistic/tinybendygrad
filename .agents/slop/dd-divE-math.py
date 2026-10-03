#!/usr/bin/env python3
# dd-divE-math.py -- evaluate the port's `f2f_clamp_max` formula (dtype.bend:1165-1177)
# and dtype.py's (dtype.py:128-131) side by side, in Python, and print each as
# f32 bits. The point is to name WHICH factor is wrong, not to be the oracle:
# CPython's side is confirmed by dd-divE-probe.py CALLING DD.f2f_clamp.
import struct
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.codegen.decomp import dtype as DD


def f32(x):
    try:
        return struct.unpack('I', struct.pack('f', float(x)))[0]
    except OverflowError:
        return None


def is_fnuz(dt):
    return dt in dtypes.fp8_fnuz


def is_e4m3(dt):
    return (not is_fnuz(dt)) and dtypes.finfo(dt)[0] == 4


def up(dt):
    """dtype.py:129-130."""
    e, m = dtypes.finfo(dt)
    if is_fnuz(dt): return (1 << e) - 1, (1 << m) - 1
    return ((1 << e) - 1, (1 << m) - 2) if dt == dtypes.fp8e4m3 else ((1 << e) - 2, (1 << m) - 1)


def port(dt):
    """dtype.bend:1171-1177."""
    e, m = dtypes.finfo(dt)
    ocp = is_fnuz(dt) or is_e4m3(dt)
    me = (1 << e) - (0 if ocp else 2)
    mm = (1 << m) - (0 if ocp else 2)
    num = (1 << m) + mm
    ex = (me - DD.exponent_bias(dt)) - m
    return float(num) * (2.0 ** ex), me, mm, num, ex


def port_fixed(dt):
    """dtype.bend's shape with dtype.py:129-130's TWO predicates: `max_exp` keyed on
    fnuz-or-e4m3 with -1, `max_man` keyed on e4m3 alone with -2."""
    e, m = dtypes.finfo(dt)
    me = (1 << e) - (1 if (is_fnuz(dt) or is_e4m3(dt)) else 2)
    mm = (1 << m) - (2 if is_e4m3(dt) else 1)
    num = (1 << m) + mm
    ex = (me - DD.exponent_bias(dt)) - m
    return float(num) * (2.0 ** ex)


def mutant(dt, me_delta_ocp, mm_on_ocp):
    """ONE FACTOR AT A TIME off the fix. `me_delta_ocp` is what `max_exp` subtracts
    on the ocp branch; `mm_on_ocp` says `max_man` is keyed on ocp (the original bug)
    instead of e4m3."""
    e, m = dtypes.finfo(dt)
    e4m = is_e4m3(dt)
    ocp = is_fnuz(dt) or e4m
    me = (1 << e) - (me_delta_ocp if ocp else 2)
    mm = (1 << m) - (2 if (ocp if mm_on_ocp else e4m) else 1)
    num = (1 << m) + mm
    ex = (me - DD.exponent_bias(dt)) - m
    return float(num) * (2.0 ** ex)


DTS = [dtypes.fp8e4m3, dtypes.fp8e4m3fnuz, dtypes.fp8e5m2, dtypes.fp8e5m2fnuz,
       dtypes.float16, dtypes.bfloat16, dtypes.float32, dtypes.float64]

for dt in DTS:
    ue, um = up(dt)
    ux = 2.0 ** (ue - DD.exponent_bias(dt)) * (1.0 + um / (1 << dtypes.finfo(dt)[1]))
    pv, me, mm, num, ex = port(dt)
    print(f"{dt.name:14s} py=({ue},{um}) -> {ux!r:24s} F({f32(ux)})   "
          f"port=({me},{mm}) num={num} ex={ex} -> {pv!r:24s} F({f32(pv)})   "
          f"fixed -> F({f32(port_fixed(dt))})")

print("\nTHE CONTROL. One factor off the fix at a time, per row. A mutation that moves")
print("nothing is a blind spot with a reason; both of these move named rows.\n")
for label, args in (("M1 max_exp subtracts 0 on ocp (was 1)", (0, False)),
                    ("M2 max_man keyed on ocp not e4m3", (1, True))):
    moved = []
    for dt in DTS:
        if f32(mutant(dt, *args)) != f32(port_fixed(dt)):
            moved.append(dt.name)
    print("  %-38s moves %d/8: %s" % (label, len(moved), ", ".join(moved) or "NOTHING"))