#!/usr/bin/env python3
"""Oracle for `uop/fold.bend`'s `bitcast_dims` U32-vs-I64 DECISION (the `fold.bend:509-514` comment).

Every `cpython=` expectation below is CALLED, never typed. The CPython side is the real
`tinygrad` `UOp._shape` BITCAST arm (`tinygrad/uop/ops.py:390-396`). The PORT side is the
arithmetic `bitcast_dims.put.of` / `bitcast_dims.scale` actually performs:

    i   = H.lo32(sint)          # LOW 32 BITS of the last dim
    n   = U32.mul(i, inp)       # (i*inp) mod 2**32
    ok  = U32.is_zero(U32.mod(n, out))          # None (=> raise) when not zero
    res = sint_of(U32.div(n, out))               # n // out, both operands unsigned

`H.lo32` and `U32.mul` are the two 2**32 truncations; everything else is exact. So the
model below is `& 0xFFFFFFFF` in exactly two places and CPython's own operators elsewhere.

Run:  .venv/bin/python .agents/slop/trigger/bc-oracle.py
"""

import sys

sys.path.insert(0, ".")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import UOp, Ops  # noqa: E402

M32 = 0xFFFFFFFF


def cpython(dim, inp, out):
    """The real `UOp._shape` BITCAST arm. Returns (raises, result_dim).

    `inp` is forced to 4 by building the source as an int32 BUFFER, and `out` is the
    BITCAST node's own dtype. Callers pair (inp, out) so this holds.
    """
    src = UOp(Ops.BUFFER, (), dtypes.int32, (dim,))
    bc = UOp(Ops.BITCAST, (src,), dtypes.dtype(out))
    try:
        return (False, bc.shape[-1])
    except RuntimeError:
        return (True, None)


def port(dim, inp, out):
    """What `bitcast_dims` computes: two 2**32 truncations, then unsigned div/mod."""
    i = dim & M32
    n = (i * inp) & M32
    return (n % out != 0, n // out)


def show(dim, inp, out):
    craw, cres = cpython(dim, inp, out)
    praw, pres = port(dim, inp, out)
    agree = (craw, cres) == (praw, pres)
    print(f"{'ok ' if agree else 'DIFF'} dim={dim} inp={inp} out={out} "
          f"cpython={'raise' if craw else cres} port={'raise' if praw else pres}")
    return agree


rows = agree = 0

# The cases the comment's claim covers: a dim is a non-negative count, so i*inp < 2**32.
print("--- non-negative dims, product under 2**32 ---")
for dim in (0, 1, 2, 3, 5, 8, 16, 1024, 65535, 1 << 20, (1 << 29) - 1):
    for inp, out in ((1, 8), (2, 8), (4, 8), (8, 4), (4, 2), (8, 1)):
        rows += 1
        agree += show(dim, inp, out)

# The first product that leaves a U32.
print("--- product >= 2**32 ---")
for dim in (1 << 29, (1 << 30) - 1, 1 << 30, (1 << 31), (1 << 32) - 1, 1 << 32, (1 << 33)):
    for inp, out in ((4, 8), (8, 4), (8, 1)):
        rows += 1
        agree += show(dim, inp, out)

# A negative last dim: upstream `isinstance(ps[-1], int)` is TRUE for a negative int, and
# `//` is FLOOR division there.
print("--- negative dims (floor division, and lo32 of a negative) ---")
for dim in (-1, -2, -3, -4, -8, -16):
    for inp, out in ((4, 8), (8, 4), (8, 1), (4, 1)):
        rows += 1
        agree += show(dim, inp, out)

print(f"\nrows={rows} agree={agree} DIFFER={rows - agree}")