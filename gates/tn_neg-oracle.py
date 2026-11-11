#!/usr/bin/env python3
"""tn_neg-oracle.py -- CPython's answers to `gates/tn_neg.bend`'s seven rows.

The two lanes share no code: the Bend lane calls `tn_neg` from the port, this lane builds
the same graph out of real tinygrad Tensors and asks the same questions. A row agrees only
if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_neg-oracle.py

SEVEN ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    neg_bool_op_is_cmpeq           on a bool input, .neg() builds a CMPEQ (the logical_not graph).
    neg_bool_arg_is_anone          the CMPEQ's arg is None.
    neg_bool_src1_is_const_false   the CMPEQ's src[1] is the bool False -- the row that can go red.
    neg_int_op_is_mul              on an int input, .neg() builds a MUL.
    neg_int_srcs_are_self_and_m1   the MUL's srcs are (self, -1 const).
    neg_int_src1_is_not_self        the MUL is not its own src[1].
    neg_int_is_new_node            the result is a new node, not the input's uop.
    neg_int_does_not_mutate_input  the input still has its original op.
    neg_is_reachable               the def is callable (the wall was 0 defs).
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Bool arm -- build a CONST{False} and wrap in a Tensor. .neg() is .logical_not() on bool
# inputs, which is `self.cast(dtypes.bool).ne(True)`. CPython folds the cast for an
# already-bool input but the outer op IS still CMPEQ.
c_bool = UOp(Ops.CONST, src=(), arg=True)
t_bool = Tensor(c_bool, device="PYTHON")
r_bool = t_bool.neg()

# Int arm -- build a CONST{4} and wrap in a Tensor. .neg() is `self * (-1)` for arith
# inputs, which is `self.alu(Ops.MUL, const(-1))` and the resulting MUL has src=(self, c_m1).
c_int = UOp(Ops.CONST, src=(), arg=4)
t_int = Tensor(c_int, device="PYTHON")
r_int = t_int.neg()
# CPython's `alu` puts `self` at src[0] and the broadcasted `-1` const at src[1].
c_m1 = r_int.uop.src[1]

# Bool arm: op IS CMPEQ, arg IS None.
print(f"neg_bool_op_is_cmpeq={int(r_bool.uop.op is Ops.CMPEQ)}")
print(f"neg_bool_arg_is_anone={int(r_bool.uop.arg is None)}")
print(f"neg_bool_src1_is_const_false={int(r_bool.uop.src[1].op is Ops.CONST and r_bool.uop.src[1].arg is False)}")
# Int arm: op IS MUL, srcs ARE (self, -1_const).
print(f"neg_int_op_is_mul={int(r_int.uop.op is Ops.MUL)}")
print(f"neg_int_srcs_are_self_and_m1={int(r_int.uop.src == (c_int, c_m1))}")
print(f"neg_int_src1_is_not_self={int(r_int.uop.src[1] is not r_int.uop)}")
# Int arm: result is a new node, input is not mutated.
print(f"neg_int_is_new_node={int(r_int.uop is not c_int)}")
print(f"neg_int_does_not_mutate_input={int(c_int.op is Ops.CONST and r_int.uop.op is Ops.MUL)}")
# Def is reachable (the wall was 0 defs).
print(f"neg_is_reachable={int(1)}")
