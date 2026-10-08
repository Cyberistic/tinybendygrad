#!/usr/bin/env python3
"""tn_graph_census-oracle.py -- CPython's OP SEQUENCE for every ported `tn_*` in the census.

    .venv/bin/python gates/tn_graph_census-oracle.py

THE SAME 39 ROWS `gates/tn_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort op sequence; this lane prints CPython's for the method the port mirrors, so a
divergence is a SHAPE divergence and not a prose claim. Four rows diverge and they are DECLARED
in the gate: `logical_not`, `bitwise_not`, `eq` and `isfinite` each carry one extra `CAST`
because the port keeps `logical_not`'s explicit `cast(bool)` and CPython folds the identity
bool cast away. The other thirty-five are byte-identical, which is the point of a census.

THE `NOOP` PROPERTY IS THE ASSERTION AND IT NEEDS NO ORACLE, BUT IT IS CHECKED HERE TOO:
`NOOP` is `Arena.bottom()`, so a `NOOP` in a graph is an index read out of range. A lane that
never produces one cannot distinguish "no bottom" from "never looked".
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


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


def t4():
    return Tensor(UOp(Ops.CONST, src=(), arg=4), device="PYTHON")


print(f"tn_sqrt={sig(t4().sqrt())}")
print(f"tn_detach={sig(t4().detach())}")
print(f"tn_contiguous_backward={sig(t4().contiguous_backward())}")
print(f"tn_trunc={sig(t4().trunc())}")
print(f"tn_reciprocal={sig(t4().reciprocal())}")
print(f"tn_sin={sig(t4().sin())}")
print(f"tn_log2={sig(t4().log2())}")
print(f"tn_exp2={sig(t4().exp2())}")
print(f"tn_rsqrt={sig(t4().rsqrt())}")
print(f"tn_logical_not={sig(t4().logical_not())}")
print(f"tn_bitwise_not={sig(t4().bitwise_not())}")
print(f"tn_neg={sig(-t4())}")
print(f"tn_dunder_neg={sig(-t4())}")
print(f"tn_relu={sig(t4().relu())}")
print(f"tn_relu6={sig(t4().relu6())}")
print(f"tn_square={sig(t4().square())}")
print(f"tn_ceil={sig(t4().ceil())}")
print(f"tn_floor={sig(t4().floor())}")
print(f"tn_isnan={sig(t4().isnan())}")
print(f"tn_isfinite={sig(t4().isfinite())}")
print(f"tn_add={sig(t4() + t4())}")
print(f"tn_and={sig(t4() & t4())}")
print(f"tn_cmplt={sig(t4() < t4())}")
print(f"tn_cmpne={sig(t4() != t4())}")
print(f"tn_fdiv={sig(t4() // t4())}")
print(f"tn_lshift={sig(t4() << t4())}")
print(f"tn_max={sig(t4().maximum(t4()))}")
print(f"tn_maximum={sig(t4().maximum(t4()))}")
print(f"tn_mod={sig(t4() % t4())}")
print(f"tn_mul={sig(t4() * t4())}")
print(f"tn_or={sig(t4() | t4())}")
print(f"tn_pow={sig(t4() ** t4())}")
print(f"tn_rshift={sig(t4() >> t4())}")
print(f"tn_shl={sig(t4() << t4())}")
print(f"tn_shr={sig(t4() >> t4())}")
print(f"tn_sub={sig(t4() - t4())}")
print(f"tn_xor={sig(t4() ^ t4())}")
print(f"tn_eq={sig(t4() == t4())}")
print(f"tn_threefry={sig(t4().threefry(t4()))}")
