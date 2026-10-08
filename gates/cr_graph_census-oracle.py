#!/usr/bin/env python3
"""cr_graph_census-oracle.py -- CPython's OP SEQUENCE for every ported public `cr_*`.

    .venv/bin/python gates/cr_graph_census-oracle.py

THE SAME ROWS `gates/cr_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort signature; this lane prints CPython's for the METHOD the port mirrors, so a
divergence is a SHAPE divergence and not a prose claim.

THE POPULATION IS DISCOVERED, NOT LISTED. `cr_<n>` is a row iff CPython's
`tinygrad/mixin/creation.py` defines a METHOD `<n>(self` / `<n>(cls`:

    for n in $(grep -o '^def cr[a-z_0-9]*' tinybendygrad/mixin/creation.bend \\
               | sed 's/^def cr_//' | sort -u); do
      grep -qE "^ *def ${n}\\(self|^ *def ${n}\\(cls" tinygrad/mixin/creation.py && echo $n
    done | wc -l        # 10

39 distinct `cr_*` def prefixes; 10 mirror a method. `const` is a `raise NotImplementedError`
and has no def here; `_multi_like` is the multi-device arm (W2) and has no def here either.

THE TEN BASE ROWS ARE ONE PER METHOD. THE EIGHTEEN `_v` ROWS ARE VARIANTS -- the fixtures that
reach the arms the default call does not: the identity reshape (`empty(4)`), the 0-dim shape
(`empty()`), the one-element shape arg that is a BARE CONST and not a STACK (`full((4,),7)`),
`buffer=False` (the EXPAND root), the weak-dtype CAST (`dtype=half`, `dtype=int32`), the bool
and float CONSTs, and the `*_like` methods on an INT32 and a BOOL receiver. The sibling
`ew_graph_census` adds two such variants beyond its 43 methods; these are named `_v` so the
count is auditable.

THE FIXTURES ARE THE PORT'S OWN. `Tensor([[1.,2.],[3.,4.]], device='PYTHON')` is ONE BUFFER and
its RESHAPE -- the same nodes `cr_fx2d` builds -- and `Tensor([1,2,3,4])` is `mo_i1d`.
`UOp.const` hash-conses, so the two lanes see the same distinct nodes.

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph -- a `toposort()` with the
node count, the root's op and src COUNT, and the root's src op sequence -- so no device is
needed and the oracle is pure Python.
"""

from tinygrad import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import Ops, UOp


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
    """The port's `O.Rng.sig`: `<len> Ops.<ROOT>/<nsrc> <src ops>`, srcs joined by a space."""
    s = seq(r.uop)
    srcs = " ".join("Ops." + u.op.name for u in r.uop.src)
    return f"{len(s)} Ops.{r.uop.op.name}/{len(r.uop.src)} {srcs}"


def fx2d() -> Tensor: return Tensor([[1., 2.], [3., 4.]], device='PYTHON')
def fx1di() -> Tensor: return Tensor([1, 2, 3, 4], device='PYTHON')
def fx1db() -> Tensor: return Tensor([True, False, True, True], device='PYTHON')


# --- the TEN base rows, one per creation.py method.
print(f"const_like={sig(fx2d().const_like(0))}")
print(f"empty={sig(Tensor.empty(2, 3, device='PYTHON'))}")
print(f"empty_like={sig(fx2d().empty_like())}")
print(f"invalids={sig(Tensor.invalids(2, 3, device='PYTHON'))}")
print(f"full={sig(Tensor.full((2, 3), 42, device='PYTHON'))}")
print(f"full_like={sig(fx2d().full_like(9))}")
print(f"zeros={sig(Tensor.zeros(2, 3, device='PYTHON'))}")
print(f"zeros_like={sig(fx2d().zeros_like())}")
print(f"ones={sig(Tensor.ones(2, 3, device='PYTHON'))}")
print(f"ones_like={sig(fx2d().ones_like())}")

# --- the VARIANTS: the arms the default call does not reach.
print(f"empty_v4={sig(Tensor.empty(4, device='PYTHON'))}")
print(f"empty_v0={sig(Tensor.empty(device='PYTHON'))}")
print(f"full_v4={sig(Tensor.full((4,), 7, device='PYTHON'))}")
print(f"full_vnobuf={sig(Tensor.full((2, 3), 42, buffer=False, device='PYTHON'))}")
print(f"full_v0nobuf={sig(Tensor.full((), 42, buffer=False, device='PYTHON'))}")
print(f"full_vhalf={sig(Tensor.full((2, 3), 42, dtype=dtypes.half, device='PYTHON'))}")
print(f"full_vbool={sig(Tensor.full((2, 3), True, device='PYTHON'))}")
print(f"full_vfloat={sig(Tensor.full((2, 3), 42.0, device='PYTHON'))}")
print(f"zeros_vi32={sig(Tensor.zeros((2, 3), dtype=dtypes.int32, device='PYTHON'))}")
print(f"ones_vi32={sig(Tensor.ones((2, 3), dtype=dtypes.int32, device='PYTHON'))}")
print(f"full_like_vhalf={sig(fx2d().full_like(9, dtype=dtypes.half))}")
print(f"full_like_vnobuf={sig(fx2d().full_like(9, buffer=False))}")
print(f"empty_like_vhalf={sig(fx2d().empty_like(dtype=dtypes.half))}")
print(f"zeros_like_vi={sig(fx1di().zeros_like())}")
print(f"empty_like_vi={sig(fx1di().empty_like())}")
print(f"const_like_v0d={sig(Tensor(7, device='PYTHON').const_like(0))}")
print(f"zeros_like_vbool={sig(fx1db().zeros_like())}")
print(f"ones_like_vbool={sig(fx1db().ones_like())}")
