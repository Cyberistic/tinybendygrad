#!/usr/bin/env python3
"""replace-oracle.py -- CPython's answers to `gates/replace.bend`'s eight rows.

The two lanes share no code: the Bend lane calls `O.UOp.replace` from the port, this
lane builds the same graphs out of real tinygrad UOps and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/replace-oracle.py

EIGHT ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    identity_returns_self         replace() with no kwargs returns the SAME UOp (id equal).
    replace_op_sets_op            replace(op=Ops.ADD) sets the op to ADD.
    replace_src_sets_srcs         replace(src=(c,)) sets srcs to (c,).
    replace_arg_sets_arg          replace(arg=...) sets the arg.
    replace_tag_sets_tag          replace(tag=...) sets the tag.
    replace_src_two_elements      replace(src=(b,a)) sets srcs to (b,a) (reversed).
    replace_op_actually_changes_op the new op is NOT the original op.
    replace_arg_to_anone          replace(arg=None) on a CONST with arg=ConstInt sets arg=None.
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp

c0 = UOp.const(7, dtypes.int)
c1 = UOp.const(3, dtypes.int)
# `c0 + c1` raises a dtype error because `+` needs both operands as the same type. Build the
# ALU directly:
alu = UOp(Ops.ADD, src=(c0, c1))

# ROW 1: identity.
r1 = c0.replace()
print(f"identity_returns_self={int(r1 is c0)}")

# ROW 2: replace(op=Ops.ADD) sets op to ADD.
r2 = c0.replace(op=Ops.ADD)
print(f"replace_op_sets_op={int(r2.op is Ops.ADD)}")

# ROW 3: replace(src=(c0,)) sets srcs to (c0,).
r3 = c1.replace(src=(c0,))
print(f"replace_src_sets_srcs={int(r3.src == (c0,))}")

# ROW 4: replace(arg=...) sets the arg.
r4 = c0.replace(arg=None)
print(f"replace_arg_sets_arg={int(r4.arg is None)}")

# ROW 5: replace(tag=True) sets the tag to True.
r5 = c0.replace(tag=True)
print(f"replace_tag_sets_tag={int(r5.tag is True)}")

# ROW 6: replace(src=(c1, c0)) sets srcs to (c1, c0) -- reversed from (c0, c1).
r6 = alu.replace(src=(c1, c0))
print(f"replace_src_two_elements={int(r6.src == (c1, c0))}")

# ROW 7: the new op is NOT the original op.
r7 = c0.replace(op=Ops.ADD)
print(f"replace_op_actually_changes_op={int(r7.op is not c0.op)}")

# ROW 8: replace(arg=None) on a CONST with arg=ConstInt sets arg=None.
r8 = c0.replace(arg=None)
print(f"replace_arg_to_anone={int(r8.arg is None)}")
