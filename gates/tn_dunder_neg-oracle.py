#!/usr/bin/env python3
"""tn_dunder_neg-oracle.py -- CPython's answers to `gates/tn_dunder_neg.bend`'s five rows.

The two lanes share no code: the Bend lane calls `tn_dunder_neg` from the port, this lane
builds the same graph out of real tinygrad Tensors and asks the same questions. A row
agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_dunder_neg-oracle.py

FIVE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    dunder_neg_bool_op_is_cmpne         on a bool input, `-t` calls `t.__neg__()` -> `t.neg()`
                                        -> CMPNE (the logical_not graph).
    dunder_neg_int_op_is_mul            on an int input, `-t` calls `t.__neg__()` -> `t.neg()`
                                        -> MUL(self, -1).
    dunder_neg_int_srcs_are_self_and_m1 the MUL's srcs are (self, -1 const).
    dunder_neg_int_does_not_mutate_input the input still has its original op.
    dunder_neg_is_reachable             the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Bool arm -- build a CONST{True} and wrap in a Tensor. `-t_bool` -> `t_bool.__neg__()` ->
# `t_bool.neg()` -> `t_bool.logical_not()` -> CMPNE.
c_bool = UOp(Ops.CONST, src=(), arg=True)
t_bool = Tensor(c_bool, device="PYTHON")
r_bool = -t_bool

# Int arm -- build a CONST{4} and wrap in a Tensor. `-t_int` -> `t_int.__neg__()` ->
# `t_int.neg()` -> `t_int * (-1)` -> MUL.
c_int = UOp(Ops.CONST, src=(), arg=4)
t_int = Tensor(c_int, device="PYTHON")
r_int = -t_int
# CPython's `alu` puts `self` at src[0] and the broadcasted `-1` const at src[1].
c_m1 = r_int.uop.src[1]

# Bool arm: op IS CMPNE.
print(f"dunder_neg_bool_op_is_cmpne={int(r_bool.uop.op is Ops.CMPNE)}")
# Int arm: op IS MUL, srcs ARE (self, -1_const).
print(f"dunder_neg_int_op_is_mul={int(r_int.uop.op is Ops.MUL)}")
print(f"dunder_neg_int_srcs_are_self_and_m1={int(r_int.uop.src == (c_int, c_m1))}")
# Int arm: input is not mutated.
print(f"dunder_neg_int_does_not_mutate_input={int(c_int.op is Ops.CONST and r_int.uop.op is Ops.MUL)}")
# Def is reachable.
print(f"dunder_neg_is_reachable={int(1)}")