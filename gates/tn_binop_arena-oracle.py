#!/usr/bin/env python3
"""tn_binop_arena-oracle.py -- CPython's answers to `gates/tn_binop_arena.bend`'s eight rows.

    .venv/bin/python gates/tn_binop_arena-oracle.py

CPython asks the same identity question `tn_add` is asked: is `src[1]` the node the caller
passed as the right operand, at that operand's depth in its own arena? CPython answers 1 at
all three depths, because a `UOp` IS its identity -- there is no index to misread.

THE TWO ROWS THAT DIVERGE ARE DECLARED, NOT SMOOTHED. `src1_is_caller_operand_at1` and
`src1_is_caller_operand_at2` are 1 here and 0 in the port, and `src1_op_is_noop_at2` is 0
here and 1 in the port. The port builds with `tn_alu(lhs, OP, [rhs.u])`, which builds in
`lhs.ar` and reads `rhs.u` THERE, and `Arena` is an immutable `Data` value so an index is
legal only in an arena descending from the one that minted it. The wall is at
`tensor.bend`'s SIBLING ARENAS block and the primitive it needs -- an arena merge -- does
not exist: no `def Arena.*` in `uop/ops.bend` takes a second arena.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def const_at(v: int) -> Tensor:
    return Tensor(UOp(Ops.CONST, src=(), arg=v), device="PYTHON")


def d0() -> Tensor:
    return const_at(5)


def d1() -> Tensor:
    return -const_at(5)


def d2() -> Tensor:
    return -(-const_at(5))


print(f"src1_is_caller_operand_at0={int((const_at(3) + d0()).uop.src[1].op is d0().uop.op)}")
print(f"src1_is_caller_operand_at1={int((const_at(3) + d1()).uop.src[1].op is d1().uop.op)}")
print(f"src1_is_caller_operand_at2={int((const_at(3) + d2()).uop.src[1].op is d2().uop.op)}")
print(f"src1_op_is_const_at0={int((const_at(3) + d0()).uop.src[1].op is Ops.CONST)}")
print(f"src1_op_is_noop_at2={int((const_at(3) + d2()).uop.src[1].op is Ops.NOOP)}")
for depth in (0, 1, 2):
    d = (d0, d1, d2)[depth]()
    r = (const_at(3) + d).uop
    print(f"src0_is_caller_lhs_at{depth}={int(r.src[0].op is const_at(3).uop.op)}")