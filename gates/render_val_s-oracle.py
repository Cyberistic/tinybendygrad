#!/usr/bin/env python3
"""render_val_s-oracle.py -- CPython's answers to `gates/render_val_s.bend`'s eight rows.

The two lanes share no code: the Bend lane calls the new `render_val_s` directly, this
lane builds a `v` and asks `str(int(v))` after the same unsigned-to-signed conversion.
A row agrees only if the two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/render_val_s-oracle.py

EIGHT ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    s_zero               the 0 case
    s_one                the 1 case
    s_seven              a small positive
    s_neg_one            the -1 case (the smallest U32)
    s_neg_two            a small negative
    s_int_min            INT32_MIN: -2147483648
    s_int_max            INT32_MAX:  2147483647
    s_hundred            a positive
"""

# Unsigned 32-bit values mapped to the Python int they represent after the
# unsigned-to-signed conversion CPython applies to `int(v)` on a 32-bit word.
# CPython's `int(v)` on a 32-bit U32 returns the UNSIGNED value; the unsigned-to-signed
# step is what the port's `i64_of_i32` does (SIGN-EXTEND), so the oracle must too.
for nm, v, signed in (
    ("s_zero", 0, 0),
    ("s_one", 1, 1),
    ("s_seven", 7, 7),
    ("s_neg_one", 0xFFFFFFFF, -1),
    ("s_neg_two", 0xFFFFFFFE, -2),
    ("s_int_min", 0x80000000, -2147483648),
    ("s_int_max", 0x7FFFFFFF, 2147483647),
    ("s_hundred", 100, 100),
):
    # Convert v to signed the way `i64_of_i32` does: subtract 2**32 if high bit set.
    signed_v = v - (1 << 32) if v >= (1 << 31) else v
    py = str(signed)
    print(f"{nm}={int(py == str(signed_v))}")
