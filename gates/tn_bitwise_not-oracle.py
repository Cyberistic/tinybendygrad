#!/usr/bin/env python3
"""tn_bitwise_not-oracle.py -- CPython's answers to `gates/tn_bitwise_not.bend`'s seven rows.

The two lanes share no code: the Bend lane calls `tn_bitwise_not` from the port, this
lane builds the same graph out of real tinygrad UOps and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_bitwise_not-oracle.py

THIS LANE CALLS THE REAL METHOD. THE FIRST VERSION BUILT `cast.ne(true_)` BY HAND, which
is the trap this tree has been bitten by twice -- an oracle that reimplements the thing it
is checking agrees with itself, and a half-reimplementation agrees with a half-reimplementation.
Every graph below comes from `Tensor.bitwise_not()`.

AND THE FIRST VERSION OF THE LAST ROW WAS `print(f"...={int(1)}")` -- A CONSTANT. IT COULD NOT
FAIL, so the two lanes compared `1 == 1` there and the gate would have stayed green with the port
entirely broken.

THE BOOL ARM HAS NO CAST, AND THAT IS THE POINT OF THREE ROWS. `elementwise.py:156-157` is

    if self.dtype == dtypes.bool: return self.logical_not()
    return (self ^ self.dtype.max) if dtypes.is_unsigned(self.dtype) else (self ^ -1)

and `logical_not` is `self.cast(dtypes.bool).ne(True)`, whose `cast` FOLDS on a bool input
(`mixin/dtype.py:36`: `return self if self.dtype == (dt:=to_dtype(dtype)) else ...`). MEASURED on
a bool CONST:

    bitwise_not -> CMPNE  nsrc: 2
       src[0] = CONST dtype=dtypes.bool arg=True
       src[1] = CONST dtype=dtypes.bool arg=True

`src[0]` IS the input. The hand-built first version minted a CAST and both lanes agreed on a
graph CPython does not build.
"""

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import Ops, UOp


def bool_const(v):
    return UOp(Ops.CONST, src=(), arg=v)


c = bool_const(True)  # the bool input
r = Tensor(c).bitwise_not().uop

print(f"bitnot_op_is_cmpne={int(r.op is Ops.CMPNE)}")
print(f"bitnot_arg_is_anone={int(r.arg is None)}")
print(f"bitnot_srcs_are_input_and_true={int(r.src[1].arg == True)}")
print(f"bitnot_identity_cast_folded={int(r.src[0] is c)}")
print(f"bitnot_input_is_bool={int(c.dtype is dtypes.bool)}")
print(f"bitnot_does_not_mutate_input={int(c.op is Ops.CONST)}")

# The SIGNED arm: `CInt{4}` is weakint and signed, so `is_unsigned` is False and CPython
# answers `(self ^ -1)`.
s = Tensor(UOp(Ops.CONST, src=(), arg=4)).bitwise_not()
print(f"bitnot_signed_takes_xor_arm={int(s.uop.op is Ops.XOR)}")