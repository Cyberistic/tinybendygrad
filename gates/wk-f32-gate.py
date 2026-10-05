#!/usr/bin/env python3
"""wk-f32-gate.py -- the CPython gate for the I64 -> F32 conversion, `wk_i64_to_f32`.

    .venv/bin/python gates/wk-f32-gate.py

18 rows, THREE LANES, all byte-identical. CPython's answer is `float(int)`, which is
CORRECTLY ROUNDED, and the port's is a 24-bit-chunk Horner. Comparing bit patterns and not
decimals is not a preference here: the difference between the two implementations is entirely
in the last mantissa bit.

`wk_dt_const.fpure` (uop/weak.bend) is the conversion's only caller, so it is the
`weakint -> weakfloat` promotion, and `tanh` is held behind it. **THIS PRIMITIVE HAD NO GATE
AT ALL**, which is how a conversion can be wrong for every negative value in the signed range
and still be described in the tree as a rounding detail nobody had checked.

THE TABLE IS WRITTEN ONCE, in `wk-f32-rows.py`, which generates BOTH the oracle's
expectations and the Bend driver's fixtures. Every value is a (hi, lo) WORD PAIR, so nothing
is re-spelled as a decimal on the Bend side -- and a value above 2**31 needs no negative
literal, which is not a term in Bend.

THE VALUES THAT REFUTE THE OLD FORMULA ARE ALL NEGATIVE, which is the whole shape of the
bug. The old two-term sum `lo + sgn(hi) * 2**32` needed `hi` EXACTLY; f32 has 24 mantissa
bits, so `U32.to_f32(0xFFFFFFFF)` is 2**32 -- correctly rounded -- where the formula needed
4294967295, the high term collapsed to zero, and -1 and -2 BOTH converted to 4294967296.0.

AND THE GATE ASSERTS neg1 AND neg2 DIFFER. They are the two rows the old formula made
IDENTICAL, and a table that let them collapse would not have noticed. That assertion is the
one line of this gate that no amount of value-checking replaces.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, LANE_OUT as GATE_OUT, LANE_ROWS as GATE_ROWS

GATE = Gate(
    "wk-f32-gate",
    bend="wk-f32.bend",
    oracle="wk-f32-rows.py",
    rows=18,
    pins=[
        ("py", "neg1"), ("py", "neg2"), ("py", "negm32"), ("py", "i64min"),
        ("bd", "neg1"), ("bd", "neg2"), ("bd", "negm32"), ("bd", "i64min"),
    ],
)

if __name__ == "__main__":
    ok = GATE.run() == 0
    if ok:
        # neg1 and neg2 must be DIFFERENT f32s. They are the rows the old formula made
        # identical, and the oracle's two answers are different numbers, so a table that let
        # them collapse would pass a reader that had lost the magnitude.
        vals = {}
        for lane in ("py", "bd", "bn"):
            rows = dict(l.split("=", 1) for l in
                        (GATE.dir / f"{lane}{GATE_ROWS if lane == 'py' else GATE_OUT}").read_text().splitlines() if "=" in l)
            vals[lane] = (rows["neg1"], rows["neg2"])
        if vals["py"][0] == vals["py"][1]:
            print("wk-f32-gate: the ORACLE says neg1 and neg2 are the same f32 -- the table "
                  "is wrong, and the check below cannot mean anything", file=sys.stderr)
            ok = False
        for lane in ("py", "bd", "bn"):
            if vals[lane][0] == vals[lane][1]:
                print(f"wk-f32-gate: {lane} gives neg1 and neg2 the SAME f32 -- the "
                      f"magnitude was lost", file=sys.stderr)
                ok = False
    print("wk-f32-gate: 18 rows, 3 lanes byte-identical" if ok else "wk-f32-gate: FAILED")
    sys.exit(0 if ok else 1)
