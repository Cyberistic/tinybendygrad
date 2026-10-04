#!/usr/bin/env python3
"""Expectations for `const_probe.bend` and `lit_probe2.bend`, BY CALLING CPython.

I hand-typed two expectations in the first run of `const_probe.bend` and BOTH were
wrong, which is agent-core.md's table coming true a sixth time:

    sqrt_2_over_pi=False   I wanted sqrt(2/pi) = 0.7978845608028654 but I paired it
                          with `F32.div(sqrt(2), pi)` = 0.45015815807855303. The
                          CONSTANT was right and the EXPRESSION was wrong.
    inf_is_nan=False       I asserted inf != inf. It is the other way round: inf
                          EQUALS itself, and `nan_is_nan=True` in the same run is
                          the row that was actually testing NaN.

Neither was caught by reading; both were caught by the run. So nothing below is
transcribed -- including the boolean claims, which are computed here in Python's
own float semantics and printed as the string the probe should agree with.

Run:  python3 .agents/slop/mathlib/expect3.py
"""
import math
import pathlib
import struct

HERE = pathlib.Path(__file__).resolve().parent


def f32(x: float) -> float:
    """Round `x` to f32 and back -- CPython does the rounding via struct."""
    (b,) = struct.unpack(">f", struct.pack(">f", x))
    return b


def main() -> int:
    half_pi = f32(math.pi / 2)
    inv_log2 = f32(1 / math.log(2))

    rows = [
        # name, what the probe computes, expected Bool
        ("half_pi_is_literal", f"is_eq({half_pi!r}, {f32(math.pi / 2)!r})",
         f32(math.pi / 2) == f32(math.pi / 2)),
        ("inv_log2_is_literal", f"is_eq({inv_log2!r}, {f32(1 / math.log(2))!r})",
         f32(1 / math.log(2)) == f32(1 / math.log(2))),
        ("half_pi_ne_pi", f"ne({half_pi!r}, {math.pi!r})", half_pi != f32(math.pi)),
        ("inv_log2_ne_log2", f"ne({inv_log2!r}, {math.log(2)!r})",
         inv_log2 != f32(math.log(2))),
        ("log2_ne_log10_2", f"ne({math.log(2)!r}, {math.log10(2)!r})",
         f32(math.log(2)) != f32(math.log10(2))),
        # THE FIX: sqrt(2/pi) is sqrt(2) OVER sqrt(pi), not over pi.
        ("sqrt_2_over_sqrt_pi",
         f"is_eq({f32(math.sqrt(2) / math.sqrt(math.pi))!r}, "
         f"{f32(math.sqrt(2 / math.pi))!r})",
         f32(math.sqrt(2) / math.sqrt(math.pi)) == f32(math.sqrt(2 / math.pi))),
        ("gelu_c", "is_eq(0.044715, 0.044715)", True),
        # THE OTHER FIX: inf equals itself. NaN is the one that does not.
        ("inf_eq_self", f"is_eq({math.inf!r}, {math.inf!r})", math.inf == math.inf),
        ("inf_x_0_is_nan", f"ne({math.inf * 0.0!r}, {math.inf!r})",
         math.inf * 0.0 != math.inf),
        ("nan_ne_self", f"ne({math.nan!r}, {math.nan!r})", not (math.nan == math.nan)),
    ]
    lines = [f"{n:<20} {b}" for n, _, b in rows]
    text = "\n".join(lines) + "\n"
    (HERE / "expect3.txt").write_text(text)
    print("the f32 values the probe must produce, as CPython rounds them:")
    for n, v, _ in rows:
        print(f"  {n:<20} {v}")
    print()
    print("expected Bool column:")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())