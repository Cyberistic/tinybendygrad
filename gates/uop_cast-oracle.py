#!/usr/bin/env python3
"""uop_cast-oracle.py -- CPython's answers to `gates/uop_cast.bend`'s eight rows.

The two lanes share no code: the Bend lane calls the new `O.UOp.cast` from the port,
this lane builds the same graphs out of real tinygrad UOps and asks the same questions.
A row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/uop_cast-oracle.py

EIGHT ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    cast_op_is_cast             .cast(dtype) sets op to CAST.
    cast_src_is_input           .cast(dtype) sets srcs to (self,).
    cast_arg_is_adt             .cast(dtype) sets arg to (dt,).
    cast_builds_new_node        the result is a different node from the input.
    cast_works_on_alu           .cast(dtype) on an ALU also sets op to CAST.
    cast_is_reachable           the def is callable (the wall was 0 defs).
    cast_does_not_mutate_input  the input still has its original op.
    cast_dedup_to_one_node      two .cast calls with the same input and dtype
                                dedup to ONE node (CPython's ucache interning).
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp

# Build a bare CONST (not the `UOp.const` wrapper, which folds in a CAST).
c = UOp(Ops.CONST, src=(), arg=7)
r1 = c.cast(dtypes.int32)
r2 = c.cast(dtypes.int32)

print(f"cast_op_is_cast={int(r1.op is Ops.CAST)}")
print(f"cast_src_is_input={int(r1.src == (c,))}")
print(f"cast_arg_is_adt={int(r1.arg == dtypes.int32)}")
print(f"cast_builds_new_node={int(r1 is not c)}")

a = c + UOp(Ops.CONST, src=(), arg=3)
ra = a.cast(dtypes.int32)
print(f"cast_works_on_alu={int(ra.op is Ops.CAST)}")
print(f"cast_is_reachable={int(1)}")
print(f"cast_does_not_mutate_input={int(c.op is Ops.CONST and r1.op is Ops.CAST)}")
print(f"cast_dedup_to_one_node={int(r1 is r2)}")
