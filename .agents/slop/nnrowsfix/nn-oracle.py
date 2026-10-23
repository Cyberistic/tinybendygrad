#!/usr/bin/env python3
"""nn-oracle.py -- CPython's OWN answers for the 31 `nn/layers.bend` rows.

    .venv/bin/python .agents/slop/nnrowsfix/nn-oracle.py > .agents/slop/nnrowsfix/nn-oracle.rows

ONE WITNESS FOR EVERY ROW. The port's rows print `nm got=<...> want=<...>`, and this
script prints `nm=<want>` for the same 31 names, where every `want` is CPython's
answer SPELLED IN THE PORT'S SPELLING. Nothing here is transcribed from the port's
output: the values come from `tinygrad` in this repo's `.venv`.

THE PORT'S SPELLINGS, AND WHERE EACH ONE COMES FROM.

  SHAPE   `MX.mx_show` (tinybendygrad/mixin/movement.bend:878) is
          `String.join(mx_shows.go(xs, Nil{}), ",")` -- the dims joined by a comma,
          with NO parentheses. CPython's `Tensor.shape` is a TUPLE, so it prints
          `(1, 4, 8, 8)`; the port prints `1,4,8,8`. The VALUE is CPython's dims.

  DTYPE   `E.ew_dtnm` (tinybendygrad/mixin/elementwise.bend:1033) returns the `nm`
          field of `S.Dt`, and `S.single()` (tinybendygrad/LAWS/spec.bend:741) is
          `Dt{14, 32, CFloat{}, "f32"}`. CPython's own `DType.name` for float32 is
          "f32" (tinygrad/dtype.py:136: `f32: Final[DType] = DType.new(14, 32,
          "f32", 'f')`); `float32` is the ALIAS (dtype.py:140), not the name. So
          the port's spelling and CPython's NAME are the same string.

  GRAPH   `MX.mxw_sig` (tinybendygrad/mixin/movement.bend:1380) is
          `n=<count> op=Ops.<root> nsrc=<n> srcops=Ops.<a>|Ops.<b>`. This script
          renders CPython's graph in that spelling. The oracle's OWN format
          (`gates/mixin-op-oracle.py`: `n OP/nsrc OP/nsrc ...`) is a DIFFERENT
          format and cannot be the port's `want`, so both are printed here.

THE FIXTURES ARE THE PORT'S FIXTURES. The port's `nn_row.t(ns, slot, size)` is
`mxw_reshape(mxw_buf(ar, slot, size), ns)`: a BUFFER of `size` elements RESHAPED to
`ns`. CPython's `Tensor(np.zeros(size), device="NPY")` is
`UOp.new_buffer("NPY", size, dtype).reshape(shape)` (tinygrad/tensor.py:37-40) --
upstream's `Ops.BUFFER`, whose size is a CONST SRC (tinygrad/uop/ops.py:830-832),
which is exactly what the port's `mxw_buf` builds
(`O.UOp.new.param(ar, O.OpsBUFFER{}, Some{size}, O.AParam{mxw_pbuf(slot)}, ...)`).

`device="NPY"` MATTERS and it is not a convenience: with the default device the
tensor is COPIED off the numpy buffer and CPython's graph grows an `Ops.COPY`
node (7 nodes instead of 6). The port's `mxw_buf` has no such COPY, so the
witness must not have one either.
"""
import sys

import numpy as np

sys.path.insert(0, '.')
from tinygrad import Tensor  # noqa: E402
from tinygrad.helpers import resolve_pool_pads  # noqa: E402


def buf(size, shape=None):
    """THE PORT'S `nn_row.t(shape, slot, size)`: a BUFFER of `size`, RESHAPED to `shape`."""
    t = Tensor(np.zeros(size, dtype=np.float32), device="NPY")
    return t if shape is None else t.reshape(shape)


def shape(t):
    """THE PORT'S SHAPE SPELLING: `MX.mx_show`, dims joined by `,`, no parentheses."""
    return ",".join(str(d) for d in t.shape)


def dtype(t):
    """THE PORT'S DTYPE SPELLING: `E.ew_dtnm`, which is CPython's `DType.name`."""
    return t.dtype.name


def sig(t):
    """THE PORT'S SIGNATURE SPELLING: `MX.mxw_sig`."""
    us = t.uop.toposort()
    root = t.uop
    srcops = "|".join("Ops." + s.op.name for s in root.src)
    return f"n={len(us)} op=Ops.{root.op.name} nsrc={len(root.src)} srcops={srcops}"


def oracle_sig(t):
    """CPython's graph in the ORACLE's spelling (`gates/mixin-op-oracle.py`)."""
    us = t.uop.toposort()
    return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def constval(v):
    """THE ORACLE'S CONST PAYLOAD SPELLING (`gates/mixin-op-oracle.py`)."""
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, int):
        return f"i{v}"
    if isinstance(v, float):
        return f"f{v:.6f}"
    return "x"


def oracle_valsig(t):
    """CPython's graph in the ORACLE's spelling, WITH the CONST payloads.

    The port's `M.mo_valsig.of` (tinybendygrad/mixin/op.bend:1255) prints the same
    thing -- `CONST/0=i3072` -- so the two node lists can be compared value by value
    and not only op by op."""
    us = t.uop.toposort()
    parts = []
    for u in us:
        s = f"{u.op.name}/{len(u.src)}"
        if u.op.name == "CONST":
            s += "=" + constval(u.arg)
        parts.append(s)
    return f"{len(us)} " + " ".join(parts) + " "


def main():
    rows = []

    # --- THE FIXTURES, once, so every row reads the same tensors.
    x = buf(6, (2, 3))
    w = buf(12, (3, 4))
    xr = x.reshape(2, 1, 3)
    wr = w.reshape(1, 3, 4).permute(0, 2, 1)
    xw = xr * wr
    sm = xw.sum(axis=2)
    cc = sm.cast("float32")
    xc = buf(3072, (1, 3, 32, 32))
    wc = buf(216, (8, 3, 3, 3))

    # --- THE SHAPE ROWS. CPython's `Tensor.shape`, the port's spelling.
    rows.append(("relu", shape(buf(256, (1, 4, 8, 8)).relu())))
    rows.append(("dot_2d", shape(x.dot(w))))
    rows.append(("dot_1d", shape(x.dot(buf(3, (3,))))))
    # `Tensor.linear(weight, bias)` takes the weight in (in, out) order and dots it;
    # `nn.Linear` stores (out, in) and transposes before calling (tinygrad/nn/__init__.py),
    # and the PORT's `nn_linear` takes the (out, in) weight and transposes it itself
    # (`nn_transpose(w)`, tinybendygrad/nn/layers.bend:521). So the witness transposes
    # here, and the port does it there -- the same operation, once each.
    rows.append(("linear", shape(buf(1152, (2, 576)).linear(
        buf(5760, (10, 576)).transpose(), buf(10, (10,))))))
    rows.append(("linear_nobias", shape(buf(1152, (2, 576)).linear(
        buf(5760, (10, 576)).transpose()))))
    rows.append(("conv_p1_s1", shape(xc.conv2d(wc, None, 1, 1, 1, 1))))
    rows.append(("conv_p0_s1", shape(xc.conv2d(wc, None, 1, 1, 1, 0))))
    rows.append(("conv_p1_s2", shape(xc.conv2d(wc, None, 1, 2, 1, 1))))
    rows.append(("conv_seq", shape(xc.conv2d(wc, None, 1, 1, 1, (1, 2)))))
    rows.append(("conv_bias", shape(xc.conv2d(wc, buf(8, (8,)), 1, 1, 1, 1))))
    rows.append(("pads_int1", ",".join(str(p) for p in resolve_pool_pads(1, 2))))
    rows.append(("pads_seq12", ",".join(str(p) for p in resolve_pool_pads((1, 2), 2))))
    rows.append(("pads_seq11", ",".join(str(p) for p in resolve_pool_pads((1, 1), 2))))
    rows.append(("shape_x", shape(buf(3072, (1, 3, 32, 32)))))
    rows.append(("where_xshape", shape(x)))
    rows.append(("where_wshape", shape(w)))
    rows.append(("fold_base", shape(x)))
    rows.append(("fold_xr", shape(xr)))
    rows.append(("fold_wr", shape(wr)))
    rows.append(("fold_xw", shape(xw)))
    rows.append(("fold_sm", shape(sm)))
    rows.append(("fold_smk", shape(xw.sum(axis=2, keepdim=True))))
    rows.append(("fold_cc", shape(cc)))

    # --- THE DTYPE ROWS. CPython's `DType.name`, which is also the port's `ew_dtnm`.
    rows.append(("where_xdt", dtype(x)))
    rows.append(("where_wdt", dtype(w)))
    rows.append(("where_dts", dtype(x.dot(w))))

    # --- THE GRAPH ROWS. CPython's graph, the port's `mxw_sig` spelling.
    rows.append(("dbg_dot_sig", sig(x.dot(w))))
    rows.append(("dbg_conv_sig", sig(xc.conv2d(wc, None, 1, 1, 1, 1))))
    rows.append(("dbg_x_sig", sig(x)))
    rows.append(("fold_cc_sig", sig(cc)))
    rows.append(("fold_xw_sig", sig(xw)))

    for name, want in rows:
        print(f"{name}={want}")

    # THE ORACLE'S OWN SPELLING, for the five graph rows, so a reader can see the
    # node LISTS and not only the counts -- and WITH the CONST payloads, which is
    # the spelling the port's `M.mo_valsig.of` prints, so the two lists can be
    # compared value by value.
    print("# ORACLE FORMAT (gates/mixin-op-oracle.py's), for the five graph rows:")
    for name, t in (("dbg_x_sig", x), ("dbg_dot_sig", x.dot(w)),
                    ("dbg_conv_sig", xc.conv2d(wc, None, 1, 1, 1, 1)),
                    ("fold_xw_sig", xw), ("fold_cc_sig", cc)):
        print(f"# {name}={oracle_sig(t)}")
    print("# ORACLE FORMAT WITH CONST PAYLOADS (the port's M.mo_valsig.of spelling):")
    for name, t in (("dbg_x_sig", x), ("dbg_dot_sig", x.dot(w)),
                    ("dbg_conv_sig", xc.conv2d(wc, None, 1, 1, 1, 1)),
                    ("fold_xw_sig", xw), ("fold_cc_sig", cc)):
        print(f"# {name}={oracle_valsig(t)}")


if __name__ == '__main__':
    main()
