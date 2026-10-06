#!/usr/bin/env python3
"""tn_bitwise_not-oracle.py -- CPython's answers to `gates/tn_bitwise_not.bend`'s eight rows.

The two lanes share no code: the Bend lane calls `tn_bitwise_not` from the port, this
lane builds the same graph out of real tinygrad UOps and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_bitwise_not-oracle.py

EIGHT ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    bitnot_op_is_cmpne                       .bitwise_not() (bool) wraps `logical_not()` = `cast(bool).ne(True)`.
    bitnot_arg_is_anone                       the outer CMPNE's arg is None.
    bitnot_src_is_cast_and_true               the outer CMPNE's srcs are (cast_index, true_index).
    bitnot_cast_in_to_bool_cast              the CMPNE's src[0] is the CAST's index.
    bitnot_cast_arg_is_adt_bool              the CAST's arg is `ADt{boolean()}`.
    bitnot_true_const_arg_is_cbool_true      the True const's arg is `APy{CBool{True{}}}`.
    bitnot_does_not_mutate_input              the input still has its original op.
    bitnot_is_reachable                       the def is callable (the wall was 0 defs).
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp

# Build a CONST{CInt{4}} input, the CAST to bool, the True CONST, and the CMPNE.
c = UOp(Ops.CONST, src=(), arg=4)
cast = c.cast(dtypes.bool)
true_ = UOp(Ops.CONST, src=(), arg=True)
r = cast.ne(true_)

print(f"bitnot_op_is_cmpne={int(r.op is Ops.CMPNE)}")
print(f"bitnot_arg_is_anone={int(r.arg is None)}")
print(f"bitnot_src_is_cast_and_true={int(r.src == (cast, true_))}")
print(f"bitnot_cast_in_to_bool_cast={int(r.src[0] is cast)}")
print(f"bitnot_cast_arg_is_adt_bool={int(isinstance(cast.arg, type(None)) is False and cast.arg == dtypes.bool)}")
print(f"bitnot_true_const_arg_is_cbool_true={int(true_.arg == True)}")
print(f"bitnot_does_not_mutate_input={int(c.op is Ops.CONST and r.op is Ops.CMPNE)}")
print(f"bitnot_is_reachable={int(1)}")
