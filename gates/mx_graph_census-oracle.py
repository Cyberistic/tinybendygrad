#!/usr/bin/env python3
"""mx_graph_census-oracle.py -- CPython's OP SEQUENCE for every ported public movement wrapper.

    .venv/bin/python gates/mx_graph_census-oracle.py

THE SAME 16 ROWS `gates/mx_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort op sequence; this lane prints CPython's for the METHOD the port mirrors, so a
divergence is a SHAPE divergence and not a prose claim.

THE POPULATION IS DISCOVERED, NOT LISTED -- see the gate's docstring for the two filters.
The five rows are the five WRITE wrappers (`reshape`/`permute`/`pad`/`shrink`/`flip`), the
whole graph-building surface of `tinygrad/mixin/movement.py`; the read half is not ported as
graph builders.

THE FIXTURE IS A RAW BUFFER AND NOT `Tensor.empty`. MEASURED: `Tensor.empty(1,4,8,8,
device='PYTHON')` is `6 Ops.RESHAPE/2 Ops.ALLOC Ops.STACK`, an ALLOC; the port's `mxw_base`
is `6 Ops.RESHAPE/2 Ops.BUFFER Ops.STACK`. Building the base from `UOp.new_buffer` makes the
two byte-identical, which matters because the five `*_noop` rows RETURN THE BASE and their
root srcs are the storage node. `UOp.new_buffer("PYTHON", 256, float)` is 0 srcs, so the
BUFFER does not change the toposort length.

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph -- a `toposort()` with each
node's op and src COUNT -- so no device is needed and the oracle is pure Python.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor
from tinygrad.dtype import dtypes


def seq(u, seen=None, out=None):
    if seen is None:
        seen, out = set(), []
    if id(u) in seen:
        return out
    seen.add(id(u))
    for s in u.src:
        seq(s, seen, out)
    out.append(u.op.name)
    return out


def sig(r) -> str:
    s = seq(r.uop)
    srcs = " ".join("Ops." + u.op.name for u in r.uop.src)
    return f"{len(s)} Ops.{r.uop.op.name}/{len(r.uop.src)} {srcs}"


def base() -> Tensor:
    return Tensor(UOp.new_buffer("PYTHON", 256, dtypes.float)._mop(Ops.RESHAPE, (1, 4, 8, 8)))


print(f"base={sig(base())}")
print(f"reshape_1_2_8_16={sig(base().reshape(1, 2, 8, 16))}")
print(f"reshape_1_4_64={sig(base().reshape(1, 4, 64))}")
print(f"reshape_noop={sig(base().reshape(1, 4, 8, 8))}")
print(f"reshape_256={sig(base().reshape(256))}")
print(f"permute_1_0_2_3={sig(base().permute(1, 0, 2, 3))}")
print(f"permute_3_1_2_0={sig(base().permute(3, 1, 2, 0))}")
print(f"permute_noop={sig(base().permute(0, 1, 2, 3))}")
print(f"pad_1_1={sig(base().pad(((0, 0), (0, 0), (1, 1), (1, 1))))}")
print(f"pad_asy={sig(base().pad(((0, 1), (0, 2), (2, 3), (1, 0))))}")
print(f"pad_noop={sig(base().pad(((0, 0), (0, 0), (0, 0), (0, 0))))}")
print(f"shrink_1_1={sig(base().shrink(((0, 0), (0, 0), (1, 5), (1, 5))))}")
print(f"shrink_asy={sig(base().shrink(((0, 1), (1, 4), (2, 7), (0, 8))))}")
print(f"shrink_noop={sig(base().shrink(((0, 1), (0, 4), (0, 8), (0, 8))))}")
print(f"flip_0={sig(base().flip(0))}")
print(f"flip_01={sig(base().flip(0, 1))}")
print(f"flip_noop={sig(base().flip(()))}")
