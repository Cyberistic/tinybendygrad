#!/usr/bin/env python3
"""invalid-tensor-oracle.py -- CPython's answers to `gates/invalid-tensor.bend`'s rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/invalid-tensor-oracle.py

THE UPSTREAM TEST THIS PORTES. `test/null/test_invalid_tensor.py` at the pin `f5ac54685074`:

    cond = UOp.const(0) < UOp.const(1)
    idx = UOp(Ops.STACK, src=tuple(UOp.const(x) for x in range(3)))
    out = cond.where(idx, UOp.invalid())
    self.assertIs(cond.op, Ops.CMPLT)
    self.assertIs(idx.op, Ops.STACK)
    self.assertIs(out.op, Ops.WHERE)
    self.assertIs(out.src[2].op, Ops.CONST)
    self.assertTrue(out.src[2].is_invalid)

THE PROPERTY IS THE TEST's NAME: `test_uop_where_keeps_invalid_bare`. THE WHERE DOES NOT FOLD
THE INVALID AWAY AND DOES NOT RE-SPELL IT AS SOMETHING ELSE -- IT IS STILL A **BARE CONST** AND
IT IS **STILL INVALID**.

NO EXPECTED VALUE IS TRANSCRIBED HERE. Every row is an answer CPython COMPUTES from its own
`tinygrad`, and the port's lane is a second implementation of the same property. The two lanes
share no code: the oracle builds real `UOp`s and asks real questions, and the port builds the
port's own `UOp`s and asks the port's own questions.

THE OPS ARE SPELLED BY NAME RATHER THAN AS BOOLEANS, because a boolean row cannot tell
`Ops.CMPLT` from `Ops.CMPEQ` from `Ops.CMPNE` -- three wrong answers that all pass a `=1`.
The oracle's names are `op.name`, which is upstream's own spelling at the pin, and the
port's names are `Ops.name.of` in `tinybendygrad/uop/ops.bend`.

THE CONSTANT is NOT ASSUMED. `UOp.const(0)` at the pin is `UOp.const(0, None)` and its dtype
is `dtypes.weakint` -- a WEAK const, which upstream's `_broadcasted` promotes to
`least_upper_dtype(weakint, weakint)`, which is `weakint`, so nothing changes. The oracle
therefore READS the dtypes rather than assuming them, and the rows that matter are the ones
that survive regardless.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tinygrad.uop.ops import Ops, UOp


def b(value: bool) -> str:
    """A 1-cell Bool as the row's value, so the two lanes' rows are comparable strings."""
    return "1" if value else "0"


def opname(op: Ops) -> str:
    """AN OP's NAME, AND NOT ITS VALUE.

    `Ops.CMPLT.name` IS `"CMPLT"` -- THE ENUM MEMBER's OWN `name`, WHICH UPSTREAM'S `auto()`
    ENUM KEEPS -- AND `Ops.name` IS **NOT** A CLASSMETHOD, SO `Ops.name(op)` IS AN
    `AttributeError`. MEASURED 2026-11-10: THE FIRST VERSION OF THIS FILE CALLED `Ops.name(op)`
    AND DIED WITH "AttributeError: <enum 'Ops'> has no attribute 'name'".

    ⇒ AND `op.name` IS UPSTREAM's OWN SPELLING AT THE PIN, SO THE ORACLE's NAMES ARE UPSTREAM's
    NAMES AND THE PORT's ARE THE PORT's OWN `Ops.name.of` -- TWO INDEPENDENT TABLES THAT MUST
    AGREE, WHICH IS WHAT MAKES THE ROW A COMPARISON AND NOT A RESTATEMENT.
    """
    return op.name


def main() -> None:
    # THE CONDITION. `UOp.const(0) < UOp.const(1)` -- upstream's `ElementwiseMixin.__lt__` at
    # the pin, which is `_binop(Ops.CMPLT, x, False)`.
    cond = UOp.const(0) < UOp.const(1)
    # THE STACK. A **RAW** STACK with three CONST srcs -- the test spells it directly rather
    # than through `UOp.group`, which at the pin is `UOp(Ops.STACK).after(*srcs)`.
    idx = UOp(Ops.STACK, src=tuple(UOp.const(x) for x in range(3)))
    # THE INVALID. `UOp.invalid()` -- ops.py:635 at the pin.
    inv = UOp.invalid()
    # THE WHERE. `cond.where(idx, UOp.invalid())` -- mixin/elementwise.py:425 at the pin.
    out = cond.where(idx, inv)

    rows = (
        ("cond_op", opname(cond.op)),
        ("cond_nsrc", str(len(cond.src))),
        ("cond_src0_op", opname(cond.src[0].op)),
        ("cond_src1_op", opname(cond.src[1].op)),
        ("idx_op", opname(idx.op)),
        ("idx_nsrc", str(len(idx.src))),
        ("idx_src0_op", opname(idx.src[0].op)),
        ("idx_src1_op", opname(idx.src[1].op)),
        ("idx_src2_op", opname(idx.src[2].op)),
        ("inv_op", opname(inv.op)),
        ("inv_is_invalid", b(inv.is_invalid)),
        ("out_op", opname(out.op)),
        ("out_nsrc", str(len(out.src))),
        ("out_src0_op", opname(out.src[0].op)),
        ("out_src1_op", opname(out.src[1].op)),
        ("out_src2_op", opname(out.src[2].op)),
        # ⇒ THE PROPERTY THE TEST IS NAMED FOR: THE THIRD SRC IS **BARE** -- A CONST -- AND IT IS
        #   **STILL INVALID** AFTER THE WHERE.
        ("out_src2_is_invalid", b(out.src[2].is_invalid)),
        # AND THE THREE WHOLE NODES SURVIVE BY IDENTITY: upstream's `_broadcasted` promotes the
        # operands to `least_upper_dtype`, which leaves a weakint STACK alone and short-circuits
        # the invalid (`if t._uop.base.is_invalid: return t`), so NOTHING is cast or replaced.
        ("out_src0_is_cond", b(out.src[0] is cond)),
        ("out_src1_is_idx", b(out.src[1] is idx)),
    )
    for name, value in rows:
        print(f"{name}={value}")


if __name__ == "__main__":
    main()
