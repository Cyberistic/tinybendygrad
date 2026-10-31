#!/usr/bin/env python3
"""uopvars-oracle.py -- the CPYTHON lane of the `is_variable` / `unbound` /
`variables` parity gate. tinygrad/uop/ops.py:1009, :1027 and :1037.

    .venv/bin/python gates/uopvars-oracle.py

THE FIXTURES ARE THE PORT'S FIXTURES, built with upstream's own constructors.
`UOp.variable()` and `UOp.range()` are upstream's, so the variable-bearing rows
are not a reconstruction: they are the thing the port is supposed to answer.

`ub_same_as_unbound` asks upstream's `is` -- hash-consing is what makes a set of
UOps dedup a BOUND Variable against its unbound form, and `is` is the only way
to say it.

`vs_dev_vmax` prints the port's `i64_text` shape (`hi:lo`) on purpose: the row
must compare the NUMBER, and both lanes are small non-negative ints here, so
`0:0..0:7` is `0..7` unambiguously on both sides.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg, AddrSpace, AxisType
from tinygrad.dtype import dtypes

STACK = UOp(Ops.STACK)


def param(slot, vmin=None, addr=AddrSpace.ALU, val=None, nm=None, img=None):
    return UOp(
        Ops.PARAM,
        src=(STACK,),
        arg=ParamArg(slot, dtypes.int32, vmin_vmax=vmin, addrspace=addr, val=val, name=nm, image=img),
    )


def hi32(v):
    return (v >> 32) & 0xFFFFFFFF


def lo32(v):
    return v & 0xFFFFFFFF


def i64t(v):
    return f"{hi32(v)}:{lo32(v)}"


def isv(u):
    return int(u.is_variable)


def varnames(u):
    return [(x.arg.name, x.arg.vmin_vmax) for x in u.variables()]


def main():
    out = []
    a = lambda nm, v: out.append(f"{nm}={v}")

    # ---- is_variable: one row per conjunct ----
    a("iv_alu_range", isv(param(0, vmin=(0, 10))))
    a("iv_alu_norange", isv(param(1)))
    a("iv_global_range", isv(param(2, vmin=(0, 10), addr=AddrSpace.GLOBAL)))
    a("iv_alu_bound", isv(param(3, vmin=(0, 10), val=5, nm="v")))
    a("iv_variable", isv(UOp.variable("v", 0, 7)))
    a("iv_alu_img", isv(param(4, vmin=(0, 10), img=(2, 2))))
    a("iv_not_param", isv(UOp.const(3)))

    # ---- unbound ----
    b = param(3, vmin=(0, 10), val=5, nm="v")
    u0 = param(3, vmin=(0, 10), nm="v")
    ub = b.unbound()
    a("ub_val_none", int(ub.arg.val is None))
    a("ub_name_kept", ub.arg.name)
    a("ub_same_as_unbound", int(ub is u0))

    # ---- variables ----
    v = UOp.variable("v", 0, 7)
    w = UOp.variable("w", 0, 3)
    a("vs_none", len(UOp.const(1).variables()))
    a("vs_one", len(v.variables()))
    a("vs_dedup", len((v + v).variables()))
    a("vs_two", len((v + w).variables()))
    a("vs_bound", len(param(9, vmin=(0, 3), val=1, nm="bv").variables()))
    rd = UOp.range(8, 0, axis_type=AxisType.DEVICE, dtype=dtypes.int32)
    rw = UOp.range(8, 1, axis_type=AxisType.WEAK, dtype=dtypes.int32)
    a("vs_device", len((rd + v).variables()))
    a("vs_weak", len((rw + v).variables()))

    # the DEVICE range ALONE, so the answer has exactly one element
    dv = rd.variables()
    a("vs_dev_count", len(dv))
    d = dv[0]
    a("vs_dev_vmax", f"{i64t(d.arg.vmin_vmax[0])}..{i64t(d.arg.vmin_vmax[1])}")
    a("vs_dev_name", d.arg.name)

    print("\n".join(out))


if __name__ == "__main__":
    sys.exit(main())
