#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/schedule/indexing.bend.

Calls tinygrad.schedule.indexing and tinygrad.uop.ops.broadcast_axes. The
movement-op rows (`mv_*`) are not printed: the port encodes them as arena slot
ids, and apply_movement_op returns UOps whose identity is not that encoding.
Printing a re-encoded arena would restate the port.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import Ops, broadcast_axes
from tinygrad.schedule.indexing import ALWAYS_CONTIGUOUS, data_srcs
from tinygrad.helpers import argsort

# Three srcs, matching ix_g3. data_srcs only reads op and the tuple's length.
SRC3 = (0, 1, 2)

# The ops g_ds probes, in the port's row-name order.
DS = [
    ("param", Ops.PARAM), ("buffer", Ops.BUFFER), ("alloc", Ops.ALLOC),
    ("range", Ops.RANGE), ("special", Ops.SPECIAL), ("index", Ops.INDEX),
    ("stage", Ops.STAGE), ("reduce", Ops.REDUCE), ("after", Ops.AFTER),
    ("end", Ops.END), ("backedge", Ops.BACKEDGE), ("copy", Ops.COPY),
    ("pad", Ops.PAD), ("shrink", Ops.SHRINK), ("flip", Ops.FLIP),
    ("expand", Ops.EXPAND), ("reshape", Ops.RESHAPE), ("permute", Ops.PERMUTE),
    ("add", Ops.ADD), ("mul", Ops.MUL), ("sink", Ops.SINK), ("const", Ops.CONST),
    ("store", Ops.STORE),
]

# g_ac's probes, including the negatives.
AC_PROBE = [
    ("after", Ops.AFTER), ("alloc", Ops.ALLOC), ("buffer", Ops.BUFFER),
    ("call", Ops.CALL), ("const", Ops.CONST), ("load", Ops.LOAD),
    ("mselect", Ops.MSELECT), ("mstack", Ops.MSTACK), ("param", Ops.PARAM),
    ("copy", Ops.COPY), ("range", Ops.RANGE),
    ("contiguous_backward", Ops.CONTIGUOUS_BACKWARD), ("store", Ops.STORE),
    ("sink", Ops.SINK), ("reshape", Ops.RESHAPE),
]

# g_bax's fixtures, indexing.bend g_bax. The raise arm is broadcast_axes's
# RuntimeError (ops.py:89), which the port prints as `raise`.
BAX = [
    ("bax0", (1,), (4,)),
    ("bax1", (1,), (1,)),
    ("bax2", (3,), (4, 3)),
    ("bax3", (1, 3), (4, 3)),
    ("bax4", (4, 3), (4, 3)),
    ("bax5", (1, 1), (4, 1)),
    ("bax6", (1, 3, 1), (4, 3, 5)),
    ("bax7", (2, 1), (2, 3)),
    ("bax8", (1, 1, 1), (2, 3, 4)),
    ("bax9", (), (2, 3)),
]


def row(name, value):
    print(f"{name}={value}")


def main():
    row("ac_n", len(ALWAYS_CONTIGUOUS))
    row("ac_sorted", ",".join(sorted(op.name for op in ALWAYS_CONTIGUOUS)))
    for nm, op in AC_PROBE:
        row("ac_" + nm, op in ALWAYS_CONTIGUOUS)

    for nm, op in DS:
        n = len(data_srcs(op, SRC3))
        row(f"ds_{nm}_srcs", n)
        row(f"ds_{nm}_has0", int(0 < n))
        row(f"ds_{nm}_has2", int(2 < n))

    for nm, src, out in BAX:
        try:
            axes = broadcast_axes(src, out)
        except RuntimeError:
            row(nm, "raise")
            continue
        row(nm, ",".join(str(i) for i in axes))
    try:
        broadcast_axes((4, 3), (4,))
        row("bax_neg", "no-raise")
    except RuntimeError:
        row("bax_neg", "raise")

    # argsort is the permutation inverse indexing.py:174 calls. Seven fixtures
    # from g_asort, including the identity and a four-element one.
    for i, perm in enumerate(((1, 0), (0, 1), (2, 0, 1), (1, 2, 0),
                              (0, 2, 1), (2, 1, 0), (3, 1, 2, 0))):
        row("argsort%d" % i, ",".join(str(j) for j in argsort(perm)))


if __name__ == "__main__":
    main()
