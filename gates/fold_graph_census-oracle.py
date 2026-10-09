#!/usr/bin/env python3
"""fold_graph_census-oracle.py -- CPython's VALUE for every fold property the port answers.

    .venv/bin/python gates/fold_graph_census-oracle.py

THE SAME FIXTURES `gates/fold_graph_census.bend` builds, read off a REAL `UOp`. Every
field is CPython's own PROPERTY -- `u.dtype`, `u._shape`, `u.base`, `u.is_invalid`,
`u.vmin`, `u.vmax` -- and NOTHING here reimplements a fold: an oracle that recomputes
the thing it is checking agrees with itself. The only thing this lane owns is the
RENDERING, which is fixed to the port's own printers so the diff is a value diff:

  * `sig`  -- `n=<toposort len> op=Ops.<name> nsrc=<k> srcops=<A|B>`, the same four
              facts `F.sig4` prints, so a fixture built with the wrong op or src count
              is caught before its value is read.
  * dtype  -- `u.dtype.name`, tinygrad's own `DType.name`, which `F.dt_nm` reads.
  * shape  -- `(d1,d2)`, `none` for `_shape is None`, `raise` for a Python raise.
  * base   -- the base NODE's op name and whether `u.base is u`.
  * invalid-- `u.is_invalid`.
  * vmin/vmax -- CPython's real `PyConst`, rendered into `F.bnd_show`'s three shapes:
              `+hi:lo`/`-hi:lo` for an integer (sign + unsigned 64-bit magnitude),
              `NInf`/`PInf` for an infinity, `F<value>` for a finite float.
"""

from tinygrad.dtype import dtypes, Invalid, AddrSpace
from tinygrad.uop.ops import UOp, Ops, ParamArg, shape_to_shape_arg, AxisType


def f32show(v: float) -> str:
    """The port's `F32.show`: an integral float prints without a fractional part."""
    return str(int(v)) if v == int(v) else repr(v)


def bnd(v) -> str:
    """CPython's `PyConst` bound, in `F.bnd_show`'s spelling."""
    if isinstance(v, float):
        if v == float("-inf"):
            return "NInf"
        if v == float("inf"):
            return "PInf"
        return "F" + f32show(v)
    if isinstance(v, bool):  # bool is an int subclass: test it FIRST
        return "+0:1" if v else "+0:0"
    if isinstance(v, int):
        sign, a = ("-", -v) if v < 0 else ("+", v)
        return f"{sign}{a >> 32}:{a & 0xFFFFFFFF}"
    return f"UNKNOWN({v!r})"


def sig(u: UOp) -> str:
    srcs = "|".join("Ops." + s.op.name for s in u.src)
    return f"n={len(list(u.toposort()))} op=Ops.{u.op.name} nsrc={len(u.src)} srcops={srcs}"


def dim_str(x) -> str:
    """A shape dim as `F.dims_str` prints it: `U(<op>:<arg>)` for a symbolic dim.

    The port's `dim_str` reads the node's OWN arg, so a PARAM prints its name and a
    SPECIAL prints its string; this is the same text from CPython's side.
    """
    if not isinstance(x, UOp):
        return str(x)
    if x.op is Ops.PARAM:
        nm = x.arg.name
    elif isinstance(x.arg, str):
        nm = x.arg
    else:
        nm = "?"
    return f"U(Ops.{x.op.name}:{nm})"


def shape_of(u: UOp) -> str:
    try:
        s = u._shape
    except Exception:
        return "raise"
    if s is None:
        return "none"
    return "(" + ",".join(dim_str(x) for x in s) + ")"


def row(nm: str, u: UOp) -> None:
    b = u.base
    print(f"{nm}={sig(u)} dtype={u.dtype.name} shape={shape_of(u)} base=Ops.{b.op.name} "
          f"self={'1' if b is u else '0'} invalid={'1' if u.is_invalid else '0'} "
          f"vmin={bnd(u.vmin)} vmax={bnd(u.vmax)}")


# --- fixture builders, one per port builder ---------------------------------------
def C(v):
    return UOp.const(v)


def BUFFER(dt, size=None, vmm=None):
    return UOp(Ops.BUFFER, (), ParamArg(0, dt, size=size, vmin_vmax=vmm))


def PARAM(dt, size=None, vmm=None):
    return UOp(Ops.PARAM, (), ParamArg(0, dt, size=size, vmin_vmax=vmm))


def RESH22(src):
    return UOp(Ops.RESHAPE, (src, shape_to_shape_arg((2, 2))))


def VAR(lo, hi, nm):
    return UOp(Ops.PARAM, (), ParamArg(0, dtypes.weakint, vmin_vmax=(lo, hi),
                                       multiple_of=1, name=nm, addrspace=AddrSpace.ALU))


if __name__ == "__main__":
    row("fold_c_int3", C(3))
    row("fold_c_int4", C(4))
    row("fold_c_float", C(1.0))
    row("fold_c_bool_t", C(True))
    row("fold_c_bool_f", C(False))
    row("fold_c_invalid", C(Invalid))
    row("fold_buf_i32", BUFFER(dtypes.i32, size=4))
    row("fold_buf_i64", BUFFER(dtypes.i64, size=2))
    row("fold_add_ii", UOp(Ops.ADD, (C(3), C(4))))
    row("fold_sub_ii", UOp(Ops.SUB, (C(3), C(4))))
    row("fold_mul_ii", UOp(Ops.MUL, (C(3), C(4))))
    row("fold_cast_i32", UOp(Ops.CAST, (C(3),), dtypes.int32))
    row("fold_stack2", UOp(Ops.STACK, (C(2), C(3))))
    row("fold_reshape22", RESH22(BUFFER(dtypes.i32, size=4)))
    row("fold_resh_resh", UOp(Ops.RESHAPE, (RESH22(BUFFER(dtypes.i32, size=4)), C(4))))
    row("fold_expand", UOp(Ops.EXPAND, (BUFFER(dtypes.i32, size=4), C(2))))
    row("fold_detach_resh", UOp(Ops.DETACH, (RESH22(BUFFER(dtypes.i32, size=4)),)))
    row("fold_range5", UOp.range(5, 0, AxisType.LOOP))
    row("fold_special4", UOp(Ops.SPECIAL, (C(4),), "N"))
    row("fold_threefry", UOp(Ops.THREEFRY, (C(0), C(0), C(0))))
    row("fold_noop_buf", UOp(Ops.NOOP, (BUFFER(dtypes.i32, size=4),)))
    row("fold_store_buf", UOp(Ops.STORE, (BUFFER(dtypes.i32, size=4), C(0))))
    row("fold_pad_param", UOp(Ops.PAD, (PARAM(dtypes.i32, size=4, vmm=(5, 9)), C(0), C(11))))
    row("fold_param_neg", PARAM(dtypes.i32, vmm=(-3, 7)))
    row("fold_expand_sym_pos", UOp(Ops.EXPAND, (BUFFER(dtypes.i32, size=4),
        UOp(Ops.STACK, (C(2), UOp(Ops.SPECIAL, (C(99),), "N"))))))
    row("fold_expand_sym", UOp(Ops.EXPAND, (BUFFER(dtypes.i32, size=4),
        UOp(Ops.STACK, (C(2), UOp(Ops.SPECIAL, (C(0),), "N"))))))
    row("fold_reshbare_n", UOp(Ops.RESHAPE, (BUFFER(dtypes.i32, size=4), VAR(0, 16777215, "n"))))
    row("fold_reshbare_w", UOp(Ops.RESHAPE, (BUFFER(dtypes.i32, size=4), VAR(0, 3, "w"))))
