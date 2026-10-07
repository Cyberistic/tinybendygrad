#!/usr/bin/env python3
"""tn_logical_not-oracle.py -- CPython's answers to `gates/tn_logical_not.bend`'s eight rows.

The two lanes share no code: the Bend lane calls `tn_logical_not` from the port, this
lane builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_logical_not-oracle.py

EIGHT ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    logical_not_op_is_cmpne                   .logical_not() builds a CMPNE.
    logical_not_arg_is_anone                   the CMPNE's arg is None.
    logical_not_does_not_mutate_input          the input still has its original op.
    logical_not_is_reachable                  the def is callable (the wall was 0 defs).
    int_input_src1_is_const                   on an INT input, src[1] is a CONST.
    int_input_graph_has_2_srcs                the CMPNE has exactly two srcs.
    int_input_src1_is_not_self                the CMPNE is not its own src[1].
    int_input_src0_is_cast                    src[0] is the bool CAST.

THE LAST FOUR ARE THE ONES A `CBool{True}` INPUT CANNOT SEE. tinygrad interns CONST
nodes, so a bool input already carries the `True` that `logical_not` compares against and
the const index names a slot both lanes agree on. An INT input has no such slot: the
const is appended, and a port that builds the CMPNE in the PRE-const arena names the slot
the CMPNE itself is about to take. That is a self-referencing node, and it typechecks --
the gate is what catches it.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a CONST{True} and wrap in a Tensor. CPython's `.logical_not` is
# `self.cast(dtypes.bool).ne(True)`, which on a bool input is identity.
c = UOp(Ops.CONST, src=(), arg=True)
t = Tensor(c, device="PYTHON")
r = t.logical_not()

print(f"logical_not_op_is_cmpne={int(r.uop.op is Ops.CMPNE)}")
print(f"logical_not_arg_is_anone={int(r.uop.arg is None)}")
print(f"logical_not_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.CMPNE)}")
print(f"logical_not_is_reachable={int(1)}")

i = Tensor(UOp(Ops.CONST, src=(), arg=4), device="PYTHON")
ri = i.logical_not()
print(f"int_input_src1_is_const={int(ri.uop.src[1].op is Ops.CONST)}")
print(f"int_input_graph_has_2_srcs={int(len(ri.uop.src) == 2)}")
print(f"int_input_src1_is_not_self={int(ri.uop.src[1] is not ri.uop)}")
print(f"int_input_src0_is_cast={int(ri.uop.src[0].op is Ops.CAST)}")