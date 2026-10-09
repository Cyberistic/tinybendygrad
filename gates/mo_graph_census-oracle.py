#!/usr/bin/env python3
"""mo_graph_census-oracle.py -- CPython's OP SEQUENCE for every public `mo_*` in the census.

    .venv/bin/python gates/mo_graph_census-oracle.py

THE SAME ROWS `gates/mo_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort op sequence; this lane prints CPython's for the METHOD the port mirrors, so a
divergence is a SHAPE divergence and not a prose claim.

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph -- a `toposort()` with each
node's op and src COUNT -- so no device is needed and the oracle is pure Python.

THE FIXTURES ARE THE PORT'S OWN. `Tensor([1.,2.,3.,4.], device='PYTHON')` is ONE BUFFER and
`Tensor([[1.,2.],[3.,4.]])` is that buffer RESHAPED -- the same two nodes `mo_fx1d` / `mo_fx2d`
build, which is why a row is comparable at all.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def sig(t) -> str:
    us = t.uop.toposort()
    return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def fx1d() -> Tensor: return Tensor([1., 2., 3., 4.], device='PYTHON')
def fx2d() -> Tensor: return Tensor([[1., 2.], [3., 4.]], device='PYTHON')

# --- the REDUCE hoist (`mixin/reduce.py`).
print(f"max0={sig(fx1d().max(axis=0))}")
print(f"max0kd={sig(fx1d().max(axis=0, keepdim=True))}")
print(f"sum0={sig(fx1d().sum(axis=0))}")
print(f"sum0kd={sig(fx1d().sum(axis=0, keepdim=True))}")
print(f"prod0={sig(fx1d().prod(axis=0))}")

# --- the ELEMENTWISE hoist (`mixin/elementwise.py`), the unary half.
print(f"neg0={sig(fx1d().neg())}")
print(f"notb0={sig(fx1d().logical_not())}")
print(f"eqc0={sig(fx1d().eq(2.0))}")
print(f"isfinite0={sig(fx1d().isfinite())}")
print(f"isnan0={sig(fx1d().isnan())}")
print(f"exp0={sig(fx1d().exp())}")
print(f"exp_i32={sig(Tensor([1, 2, 3, 4], device='PYTHON').exp())}")
print(f"log0={sig(fx1d().log())}")
print(f"recip0={sig(fx1d().reciprocal())}")
print(f"inverse0={sig(fx1d()._inverse())}")

# --- the ELEMENTWISE hoist, the binary half.
print(f"sub00={sig(fx1d() - 1.0)}")
print(f"div00={sig(fx1d() / 2.0)}")
_wt = fx1d()
print(f"where0={sig((_wt != 0.0).where(_wt, 0.0))}")

# --- the MOVEMENT hoist (`mixin/movement.py`).
print(f"reshape0={sig(fx1d().reshape(2, 2))}")
print(f"permute0={sig(fx2d().permute(1, 0))}")
print(f"squeeze0={sig(fx1d().reshape(1, 4).squeeze(0))}")

# --- the `op.py` recipes.
print(f"min0={sig(fx1d().min(axis=0))}")
print(f"mean0={sig(fx1d().mean(axis=0))}")
print(f"var0={sig(fx1d().var(axis=0))}")
print(f"std0={sig(fx1d().std(axis=0))}")
print(f"varmean0_v={sig(fx1d().var_mean(axis=0)[0])}")
print(f"varmean0_m={sig(fx1d().var_mean(axis=0)[1])}")
print(f"stdmean0_s={sig(fx1d().std_mean(axis=0)[0])}")
print(f"stdmean0_m={sig(fx1d().std_mean(axis=0)[1])}")
print(f"norm0={sig(fx2d().normalize(p=0, dim=0))}")
print(f"lse0={sig(fx1d().logsumexp(axis=0))}")
print(f"lse0kd={sig(fx1d().logsumexp(axis=0, keepdim=True))}")
print(f"softmax0={sig(fx1d().softmax(axis=0))}")
print(f"logsoftmax0={sig(fx1d().log_softmax(axis=0))}")
print(f"softmin0={sig(fx1d().softmin(axis=0))}")
_s3m, _s3e, _s3ss = fx1d()._softmax(axis=0, dtype=None)
print(f"softmax3_m={sig(_s3m)}")
print(f"softmax3_e={sig(_s3e)}")
print(f"softmax3_ss={sig(_s3ss)}")
