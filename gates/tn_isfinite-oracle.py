#!/usr/bin/env python3
"""tn_isfinite-oracle.py -- CPython's answers to `gates/tn_isfinite.bend`'s six rows.

The two lanes share no code: the Bend lane calls `tn_isfinite` from the port, this
lane builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_isfinite-oracle.py

SIX ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    isfinite_op_is_cmpne                  .isfinite() builds a CMPNE (the outer logical_not).
    isfinite_arg_is_anone                  the CMPNE's arg is None.
    isfinite_has_two_top_srcs              the top has 2 srcs (or, const{True}).
    isfinite_is_reachable                  the def is callable (the wall was 0 defs).
    isfinite_src1_is_const                 src[1] is the CONST{True} the NOT tests against.
    isfinite_src1_is_not_self              the CMPNE is not its own src[1].

THE LAST TWO ARE THE ONES THAT CAUGHT THE ARENA BUG. `logical_not` builds its CMPNE in the
arena as it stood BEFORE the `CONST{True}` was interned, which appends the CMPNE at the slot
the const index names and makes the node its own `src[1]`. Nothing about `op`/`arg`/`nsrc`
sees that, and the graph still typechecks.

THE INPUT IS AN INT, NOT A FLOAT. `O.CFloat{1.0}` in the bend driver puts `bend` over its
elaboration limit on this graph -- MEASURED, `./bin/bend` answers
`a declared datatype (unknown: IO)` and the gate REFUSES, while the identical driver with
`O.CInt` answers all six rows.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a CONST{1} and wrap in a Tensor. CPython's `.isfinite` is
# `(self.isinf() | self.isnan()).logical_not()`, so the top is a CMPNE (the
# `logical_not`'s CMPNE) whose src[0] is the OR and src[1] is CONST{True}.
c = UOp(Ops.CONST, src=(), arg=1)
t = Tensor(c, device="PYTHON")
r = t.isfinite()

print(f"isfinite_op_is_cmpne={int(r.uop.op is Ops.CMPNE)}")
print(f"isfinite_arg_is_anone={int(r.uop.arg is None)}")
print(f"isfinite_has_two_top_srcs={int(len(r.uop.src) == 2)}")
print(f"isfinite_is_reachable={int(1)}")
print(f"isfinite_src1_is_const={int(r.uop.src[1].op is Ops.CONST)}")
print(f"isfinite_src1_is_not_self={int(r.uop.src[1] is not r.uop)}")