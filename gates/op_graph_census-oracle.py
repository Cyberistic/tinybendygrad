#!/usr/bin/env python3
"""op_graph_census-oracle.py -- CPython's DEEP OP SEQUENCE (with each node's ARG) for every
graph-building def of `tinybendygrad/nn/optim.bend`.

    .venv/bin/python gates/op_graph_census-oracle.py

THE SAME 28 ROWS `gates/op_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's deep toposort for each ported builder; this lane prints CPython's for the SAME
EXPRESSION -- the real `Tensor` method / `_step` line the builder mirrors, so a divergence is a
SHAPE divergence and not a prose claim. The `_apply_update` row calls `a.detach() - g` (the real
operator), NOT `a.alu(Ops.SUB)`: CPython's `sub` is `ADD(a, -b)` (mixin/elementwise.py:121-123,
`return a.alu(Ops.ADD, -b)`), so an oracle that reached for the `SUB` enum would have agreed
with the port while BOTH were wrong.

THE PRINTER IS THE DEEP TOPOSORT PLUS EACH NODE'S ARG. `Rng.sig` prints no arg, and the layer's
headline defect (the trust guards compare against `1.0` where optim.py:115 says `0`) lives
ENTIRELY in a CONST's arg. A float CONST prints `f<bits>` with the F32 bit pattern (the port's
`F32.bits`, the oracle's `ConstFloat.bits` re-encoded to single precision), a bool prints
`b<bool>`, everything else `-`.

THE FIXTURE IS FOUR BUFFERs IN ONE GRAPH, node for node the bend lane's, and the momentum
buffer is REBUILT BEFORE EVERY ROW. `Tensor.assign` MUTATES in Python, so a single shared `bb`
would carry the previous row's STORE/AFTER into the next; the port's `op_mom` returns a new
record instead and never mutates, so the shared-`bb` lane would diverge for a reason that is
not the port's. `Tensor([1.0,2.0], device='PYTHON')` is a BUFFER. Nothing is executed.
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tinygrad import Tensor  # noqa: E402
from tinygrad.uop.ops import Ops  # noqa: E402
from tinygrad.dtype import dtypes, ConstFloat  # noqa: E402
from tinygrad.nn import optim  # noqa: E402


def carg(x) -> str:
    """A node's ARG as a value: `f<bits>` for a float CONST, `b<bool>` for a bool, `-` else.

    `ConstFloat.bits` is the DOUBLE pattern, and the port stores a single-precision `F32`, so
    the value is re-encoded to f32 before its bits are printed -- otherwise `1.0` would print
    `0x3FF0000000000000` here and `0x3F800000` there.
    """
    if x.op is Ops.CONST:
        a = x.arg
        if isinstance(a, ConstFloat):
            return "f%d" % struct.unpack("<I", struct.pack("<f", float(a)))[0]
        if isinstance(a, bool):
            return "b%d" % int(a)
        if isinstance(a, int):
            return "i"
    return "-"


def dsig(u) -> str:
    us = u.toposort()
    return f"{len(us)} " + " ".join(f"{x.op.name}/{len(x.src)}:{carg(x)}" for x in us) + " "


def row(nm, t) -> None:
    print(f"{nm}={dsig(t.uop if isinstance(t, Tensor) else t)}")


# ---- the fixture: FOUR BUFFERs (the bend lane's `fx()`), rebuilt per row where assign bites ----
def fa():
    t = Tensor([1.0, 2.0], device="PYTHON")
    t.is_param_(True)
    return t


def fg():
    return Tensor([0.5, 0.25], device="PYTHON")


def fb():
    return Tensor([0.0, 0.0], device="PYTHON")


def flr():
    return Tensor([0.1], device="PYTHON")


# ---- the four value rows (the file's own non-graph claims) ----
pa = Tensor([1.0, 2.0], device="PYTHON")
pa.is_param_(True)
pbuf = Tensor([3.0], device="PYTHON")
pbuf.is_param_(False)
pc = Tensor([4.0, 5.0, 6.0], device="PYTHON")
pc.is_param_(True)
o = optim.Optimizer([pa, pbuf, pc], lr=0.1)
print("params=%s," % ",".join(str(t.numel()) for t in o.params))
print("bufs=%s," % ",".join(str(t.numel()) for t in o.buffers))
print("acc=%s," % ",".join(str(x) for x in optim.Optimizer([pa, pc], lr=0.1, fused=True).pos_params))
print("nop=%s," % ",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param()))

# ---- the graph rows ----
a, g, bb, lr = fa(), fg(), fb(), flr()
row("detach", a.detach())
row("apply", a.detach() - g)
row("square", a * a)
row("div", a / g)
row("sqrt", a.sqrt())
row("recip", a.reciprocal())
row("neg", -a)
row("sum", a.sum())
row("normsq", (a * a).sum().sqrt())
row("cast", a.cast(dtypes.float32))
row("where", (a > 0).where(g, 1.0))
row("guard", a > 0)
row("mulf", 0.1 * a)
row("prewd", g + 0.1 * a.detach())
r1 = a.detach().square().sum().sqrt()
r2 = g.square().sum().sqrt()
row("trust", (r1 > 0).where((r2 > 0).where(0.001 * r1 / (r2 + 0.0 * r1), 1.0), 1.0))
row("lars0", g * 1.0 * lr)
mb = fb()
row("mom", mb.assign(0.9 * mb + g))
row("nesterov", g + 0.9 * fb())
row("postwd", g + 0.1 * lr * a.detach())
row("mstep", (0.9 * fb() + (1.0 - 0.9) * g).cast(dtypes.float32))
row("vstep", (0.999 * fb() + (1.0 - 0.999) * (g * g)).cast(dtypes.float32))
row("mhat", fb() / (1.0 - Tensor([0.9], device="PYTHON")))
row("vhat", fb() / (1.0 - Tensor([0.999], device="PYTHON")))
row("lamb_up", (lr * 1.0 * fb()).cast(dtypes.float32))
