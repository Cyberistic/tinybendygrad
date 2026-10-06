#!/usr/bin/env python3
"""render_val_s-gate.py -- THE GATE for `tinybendygrad/renderer/tc_ptx.bend`'s `render_val_s`.

    .venv/bin/python gates/render_val_s-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `render_val_s` does what CPython's `str(int(v))` does on a 32-bit signed value.
The wall that lived at `tc_ptx.bend:191` ("the blocker is that nobody has WIRED `i64_dec`
INTO THIS ARM -- a row, not a wall") was closed by wiring `i64_dec(i64_of_i32(v))` -- a
one-line port that uses the helpers `i64_of_i32` (SIGN-EXTEND) and `i64_dec` (gated at
`gates/i64-shl-gate.py` 301 rows, 3 lanes and `gates/i64-shr-gate.py` 151 rows, 3 lanes).

WHAT THIS IS FOR. The port had `render_val_u` (the unsigned arm) ported and gated, and
`render_val_s` (the signed arm) missing. CPython's `str(int(x))` is the unsigned arm
plus a sign, so the new arm matches the existing work. The eight rows cover the four
signs (zero, positive, negative, max-int, min-int) and the two bytes CPython's `int`
truncates on a 32-bit value. A port that always used `U32.show` would fail the three
negative rows; a port that did not sign-extend would fail `s_neg_one`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. The row NAME is the claim being asked, so it is pinned on both
# lanes: a row renamed on one lane only is a gate that stopped asking its question
# without saying so, and a value diff cannot see that at all -- same value, same verdict,
# different question.
ROWS = (
    "s_zero",        # the 0 case
    "s_one",         # the 1 case
    "s_seven",       # a small positive
    "s_neg_one",     # the -1 case (the smallest U32)
    "s_neg_two",     # a small negative
    "s_int_min",     # INT32_MIN: -2147483648
    "s_int_max",     # INT32_MAX:  2147483647
    "s_hundred",     # a positive
)

GATE = Gate(
    "render_val_s-gate",
    bend="render_val_s.bend",
    oracle="render_val_s-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "render_val_s-gate: 8 rows, 3 lanes -- render_val_s's signed "
                        "32-bit decimal printer agrees with CPython's str(int(v)) on "
                        "zero, the small positives, the small negatives, INT32_MIN, and "
                        "INT32_MAX"))