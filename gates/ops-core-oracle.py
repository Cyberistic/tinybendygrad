#!/usr/bin/env python3
"""ops-core-oracle.py -- CPython's answers to `gates/ops-core.bend`'s five rows.

Built from `tinygrad` directly, so the two lanes share no code: the Bend lane calls the five
`t_*` tests `uop/ops.bend` already contains, this lane builds the same graphs out of real tinygrad
UOps and asks the same five questions. A row agrees only if both implementations of the property
say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/ops-core-oracle.py

WHY THE IDENTITY CLAIMS ARE WORTH A ROW. tinygrad's `UOp.key` is a hash over the packed arg, so a
CONST's identity is its BIT PATTERN. IEEE equality disagrees with that in exactly two directions
and this gate pins both, which is the whole reason the port compares `F32.bits` rather than
`F32.is_eq`:

    Tensor(0.0)._uop is Tensor(-0.0)._uop   -> False   0x00000000 vs 0x80000000
    Tensor(nan)._uop is Tensor(nan)._uop   -> True    0x7fc00000 both

A port that keyed on `is_eq` would collapse two distinct nodes in the first cell and re-mint an
identical node in the second -- two different wrong answers from one comparison.
"""

from tinygrad import dtypes
from tinygrad.uop.ops import AxisType, Ops, UOp

F32 = dtypes.float32


def b(value: bool) -> str:
    """A 1-cell Bool as the row's value, so the two lanes' rows are comparable strings."""
    return "1" if value else "0"


def main() -> None:
    # `g_const` / `t_hashcons`: the same key again on an arena that already holds it.
    # CPython's UOp interns in `uop_cache`, so identity IS the hash-consing claim.
    three = UOp.const(3, dtypes.int32)
    hashcons_same_index = b(three is UOp.const(3, dtypes.int32))

    # `t_float_zeros_differ`: 0.0 and -0.0 are DIFFERENT consts. Compared as IEEE they are
    # equal, and a port that keyed on that would merge two nodes tinygrad keeps apart.
    zeros_differ = b(UOp.const(0.0, F32) is not UOp.const(-0.0, F32))

    # `t_float_nan_interns`: two NaNs are ONE node, so `is_eq` in the OTHER direction.
    nan = float("nan")
    nan_interns = b(UOp.const(nan, F32) is UOp.const(nan, F32))

    # `t_dtype_key`: a bool const and an int const are different keys. The port spells the class
    # as an explicit `Cls` tag rather than a signedness flag (`LAWS/spec.bend:54`), and this is
    # the row that says the tag is load-bearing rather than decorative.
    bool_vs_int_key = b(UOp.const(True, dtypes.bool) is not UOp.const(3, dtypes.int32))

    # `t_cycle`: the BACKEDGE reads back as itself -- src[0] is the SPECIAL it was called on and
    # src[1] the RANGE whose arg names the axis it closes over. Built through the port's own
    # shape: `UOp.special` is handed the RANGE, not a bare number.
    rng = UOp.range(UOp.const(1, dtypes.weakint), 1, AxisType.DEVICE)
    special = UOp.special(rng, "g")
    backedge = special.backedge(rng, special)
    backedge_srcs = b(backedge.src[0].op is Ops.SPECIAL and backedge.src[1].op is Ops.RANGE)

    for row in (("hashcons_same_index", hashcons_same_index),
                ("zeros_differ", zeros_differ),
                ("nan_interns", nan_interns),
                ("bool_vs_int_key", bool_vs_int_key),
                ("backedge_srcs", backedge_srcs)):
        print(f"{row[0]}={row[1]}")


if __name__ == "__main__":
    main()
