#!/usr/bin/env python3
"""tn_nary_arena-oracle.py -- CPython's answers to `gates/tn_nary_arena.bend`'s twelve rows.

    .venv/bin/python gates/tn_nary_arena-oracle.py

CPython asks the same question `tn_where` and `tn_threefry` are asked: at src position k, is
the node the CALLER passed? A `UOp` IS its identity, so there is no index to misread and
CPython answers 1 at every depth.

WHY THE GATE EXISTS. `tn_where` was `tn_alu(cond, WHERE, [x.u, y.u])`, which read both src
indices in `cond.ar`. Measured in the port with `y` at depth 1 in its own arena:
`3 Ops.WHERE/3 Ops.CONST Ops.CONST Ops.NOOP` -- `src[2]` was the bottom. `tn_threefry` had
the same defect with two operands. Both now merge first (`tensor.bend`'s SIBLING ARENAS
block), and this gate is what keeps them merged.

THE DERIVED OPERAND IS `a + a`, NOT `-a`. `-a` on a BOOL takes `tn_neg`'s logical_not arm and
builds CMPNE, which would make "derived" and "negated" the same expected op and the row would
stop discriminating.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def t_true() -> Tensor:
    return Tensor(UOp(Ops.CONST, src=(), arg=True), device="PYTHON")


def t_false() -> Tensor:
    return Tensor(UOp(Ops.CONST, src=(), arg=False), device="PYTHON")


def d0() -> Tensor:
    return t_false()


def d1() -> Tensor:
    return t_false() + t_false()


print(f"where_src0_is_caller_at_d1={int((t_true().where(t_false(), d1())).uop.src[0].op is Ops.CONST)}")
print(f"where_src1_is_caller_at_d1={int((t_true().where(t_false(), d1())).uop.src[1].op is Ops.CONST)}")
print(f"where_src2_is_caller_at_d1={int((t_true().where(t_false(), d1())).uop.src[2].op is Ops.ADD)}")
print(f"where_src0_is_caller_at_d0={int((t_true().where(d0(), d0())).uop.src[0].op is Ops.CONST)}")
print(f"where_src1_is_caller_at_d0={int((t_true().where(d0(), d0())).uop.src[1].op is Ops.CONST)}")
print(f"where_src2_is_caller_at_d0={int((t_true().where(d0(), d0())).uop.src[2].op is Ops.CONST)}")

all3 = (t_true() + t_true()).where(t_false() + t_false(), t_false() + t_false())
print(f"where_all_three_at_depth1={int(all(u.op is Ops.ADD for u in all3.uop.src))}")
print(f"where_no_src_is_noop_at_d1={int(t_true().where(t_false(), d1()).uop.src[2].op is not Ops.NOOP)}")
print(f"where_no_src_is_noop_at_d0={int(t_true().where(t_false(), d0()).uop.src[2].op is not Ops.NOOP)}")

tf = t_true().threefry(d1())
print(f"threefry_src1_is_caller_at_d1={int(tf.uop.src[1].op is Ops.ADD)}")
print(f"threefry_src0_is_caller_at_d1={int(tf.uop.src[0].op is Ops.CONST)}")
print(f"threefry_no_src_is_noop_at_d1={int(tf.uop.src[1].op is not Ops.NOOP)}")