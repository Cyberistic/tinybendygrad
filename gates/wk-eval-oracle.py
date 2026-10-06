#!/usr/bin/env python3
"""wk-eval-oracle.py -- CPython's answers to `gates/wk-eval.bend`'s sixteen rows.

Built from real tinygrad UOps, so the lanes share no code: the Bend lane calls
`wk_eval_int` / `wk_eval_float` / `wk_eval_bool` in `uop/weak.bend`, this lane calls `int()` /
`float()` / `bool()` on the same shapes and prints what CPython does with them.

    .venv/bin/python gates/wk-eval-oracle.py

WHAT `_eval` IS -- tinygrad/uop/ops.py:521. Three checks in a fixed order:

    1. assert self.dtype in dtype                 the caller's dtype SET
    2. if vmin != vmax: raise ValueError          the bounds must be a SINGLE number
    3. assert isinstance(vmin, expected_type)     the value's Python type

and the three dunders at ops.py:527-529 are `_eval` over three different sets:

    __bool__   (dtypes.bool,)
    __int__    dtypes.ints  + (dtypes.weakint,)
    __float__  dtypes.floats + (dtypes.weakfloat,)

A REFUSAL IS `none` here, and all three refusals print the same `none`, which is why every one of
them is paired with a `_dt` row: the pair is what separates "the dtype was wrong" from "the bounds
differ", and a row that could not tell them apart would let a reader that refuses for the wrong
reason pass. CPython raises where the port answers `None{}`, and the row records the OUTCOME
rather than the exception class -- `bool(u)` on an int32 raises `AssertionError` and
`int(u)` on a range raises `ValueError`, and neither distinction survives into the claim.

FORMATTING IS DELIBERATE ON BOTH SIDES. `H.i64_text` prints an I64 as its two words (`7` is
`0:7`) and `H.f32_show` prints six decimals, and this file reproduces both rather than the other
way round: `helpers.bend` says a dump the oracle can diff line for line is worth more than a
prettier one, and a prettier one would have meant a third formatter in the tree.
"""

from tinygrad import dtypes
from tinygrad.dtype import ConstFloat
from tinygrad.uop.ops import Ops, ParamArg, UOp

INTS = dtypes.ints + (dtypes.weakint,)
FLOATS = dtypes.floats + (dtypes.weakfloat,)


def param(dtype, lo, hi):
    """A PARAM carrying an explicit dtype and an explicit pair of bounds.

    The bounds are what makes the two refusals distinguishable: `lo == hi` is a single number in a
    stated dtype, so the ONLY thing that can refuse it is the dtype check, and `lo != hi` is the
    same shape refused by the range check instead.
    """
    return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtype, vmin_vmax=(lo, hi)))


def call(fn, u):
    """`_eval`'s OUTCOME, or `none`. The exception class is deliberately not recorded."""
    try:
        return str(fn(u))
    except (AssertionError, ValueError):
        return "none"


def i64_text(v: int) -> str:
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def main() -> None:
    # A CONST DERIVES ITS DTYPE FROM ITS ARG (`ops.py:637`), so these three carry the derived one
    # and need no dtype of their own: `CInt` -> weakint, `CFloat` -> weakfloat, `CBool` -> bool.
    weakint = UOp.const(7, dtypes.weakint)
    weakfloat = UOp.const(ConstFloat(0.5), dtypes.weakfloat)
    true_ = UOp.const(True, dtypes.bool)
    false_ = UOp.const(False, dtypes.bool)

    # THE THREE `int32` SHAPES, and the pair `5..5` / `1..5` is what makes the two refusals
    # distinguishable: a single number in a stated dtype can only be refused by the dtype check.
    single = param(dtypes.int32, 5, 5)
    span = param(dtypes.int32, 1, 5)
    on_i32 = param(dtypes.int32, 0, 0)
    f_on_i32 = param(dtypes.int32, 3, 3)

    def bl(dtype, allowed) -> int:
        return 1 if dtype in allowed else 0

    # THE ORDER IS THE DRIVER'S, not this file's. A lane comparison that sorts would hide a row
    # that moved between lanes, which is a change of question rather than of answer.
    print(f"int_weakint_val={call(lambda u: i64_text(int(u)), weakint)}")
    print(f"float_weakfloat_val={float(weakfloat):f}")
    print(f"bool_true_val={call(lambda u: i64_text(int(bool(u))), true_)}")
    print(f"bool_false_val={call(lambda u: i64_text(int(bool(u))), false_)}")
    print(f"int_i32_val={call(lambda u: i64_text(int(u)), single)}")
    print(f"int_on_range_val={call(lambda u: i64_text(int(u)), span)}")
    print(f"bool_on_i32_val={call(bool, on_i32)}")
    print(f"float_on_i32_val={call(float, f_on_i32)}")
    print(f"int_weakint_dt={bl(weakint.dtype, INTS)}")
    print(f"float_weakfloat_dt={bl(weakfloat.dtype, FLOATS)}")
    print(f"bool_true_dt={bl(true_.dtype, (dtypes.bool,))}")
    print(f"int_i32_dt={bl(single.dtype, INTS)}")
    print(f"int_on_range_dt={bl(span.dtype, INTS)}")
    print(f"bool_on_i32_dt={bl(on_i32.dtype, (dtypes.bool,))}")
    print(f"float_on_i32_dt={bl(f_on_i32.dtype, FLOATS)}")
    print(f"bool_false_dt={bl(false_.dtype, (dtypes.bool,))}")


if __name__ == "__main__":
    main()
