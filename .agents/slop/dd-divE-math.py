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
    """dtype.bend's shape with max_man keyed on e4m3 ALONE (dtype.py:130)."""
    e, m = dtypes.finfo(dt)
    me = (1 << e) - (1 if (is_fnuz(dt) or is_e4m3(dt)) else 2)
    mm = (1 << m) - (2 if is_e4m3(dt) else 1)
    num = (1 << m) + mm
    ex = (me - DD.exponent_bias(dt)) - m
    return float(num) * (2.0 ** ex)


for dt in [dtypes.fp8e4m3, dtypes.fp8e4m3fnuz, dtypes.fp8e5m2, dtypes.fp8e5m2fnuz,
           dtypes.float16, dtypes.bfloat16, dtypes.float32, dtypes.float64]:
    ue, um = up(dt)
    ux = 2.0 ** (ue - DD.exponent_bias(dt)) * (1.0 + um / (1 << dtypes.finfo(dt)[1]))
    pv, me, mm, num, ex = port(dt)
    print(f"{dt.name:14s} py=({ue},{um}) -> {ux!r:24s} F({f32(ux)})   "
          f"port=({me},{mm}) num={num} ex={ex} -> {pv!r:24s} F({f32(pv)})   "
          f"fixed -> F({f32(port_fixed(dt))})")