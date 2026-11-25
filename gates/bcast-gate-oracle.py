#!/usr/bin/env python3
"""bcast-gate-oracle.py -- CPython's answer for `_broadcast_to`, `mixin/bcast.bend`'s dance.

    .venv/bin/python gates/bcast-gate-oracle.py

The source is the driver's, mirrored: a BUFFER whose STACK carries the element count (so its
shape is `(n,)`, the same node `mxw_buf` mints), then `.reshape(*src)` -- the movement MIXIN's
identity-checking wrapper, which is why `b_rank_up`'s source is the BUFFER itself and not a
RESHAPE of it. `bcast-gate.bend` uses `mxw_reshape`, the same wrapper, for the same reason.

The rows are `name=<result op>/<src0 op>/<src0 dims>`. THE WRONG DANCE (one EXPAND carrying the
FULL target, which the fold reads as `marg ++ src.shape`) cannot produce these: its src0 op is
always EXPAND and its src0 dims carry `len(dst) + len(src)` dims.
"""
import math

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, ParamArg, UOp

PAIRS = (
    ("b_rank_up", (3,), (2, 3)),
    ("b_size1", (2, 1), (2, 3)),
    ("b_both", (1, 1), (2, 3)),
    ("b_id", (2, 3), (2, 3)),
)


def leaf(n: int) -> UOp:
    return UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp.const(n, dtypes.int32),)),),
               arg=ParamArg(0, dtypes.float32))


def main() -> None:
    for name, src, dst in PAIRS:
        x = leaf(math.prod(src)).reshape(*src)
        e = x.expand(*dst)
        s0 = e.src[0]
        print("%s=%s/%s/%s" % (name, e.op.name, s0.op.name, "x".join(map(str, s0.shape))))


if __name__ == "__main__":
    main()
