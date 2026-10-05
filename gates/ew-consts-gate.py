#!/usr/bin/env python3
"""ew-consts-gate.py -- the CPython gate for elementwise.bend's F32 CONSTANTS.

    .venv/bin/python gates/ew-consts-gate.py

21 rows, THREE LANES, all byte-identical. The rows are BIT PATTERNS and not decimals,
because the port has no `F64` and a decimal comparison would pass a value that rounds
differently -- which is the constants' actual failure mode, and it bit three of them.

THIS GATE EXISTS TO REFUTE A WALL, which is unusual enough to say plainly. The marker block
in elementwise.bend read "no float literal anywhere in the port, because `F32` is
`F32{data: Word(32n)}`, `Word` is not exported, and `U32.to_f32` is an unfilled LAW" -- and it
was holding up a dozen methods. All three halves are false: a literal works, `F32.pi()` is a
constant, and `U32.to_f32` is a Bend primitive that is gated 12/12 against CPython elsewhere.

THREE OF THE OBVIOUS SPELLINGS MEASURED WRONG, and that is the part worth keeping, because
it is the opposite of the intuition:
    log10(2)   `0.30102999` (EIGHT digits) is one ulp LOW. `0.30103` -- FIVE -- is right.
    selu gamma `1.0507009` (eight) is wrong. `1.050701` (seven) is right.
    sqrt(2/pi) the COMPOSITE is one ulp off, because it rounds twice where CPython rounds
               once. A LITERAL cannot double-round, so that constant is a literal.
So: MORE DIGITS IS NOT MORE ACCURATE IN F32, and a composition of f32 ops is not the f32 of
the composed real expression.

THE NEGATIVE FIXTURE IS NOT REACHABLE FROM HERE and does not need to be: this gate is about
CONSTANTS, and the conversion that made -1 and -2 identical is `wk_i64_to_f32`, gated by
`wk-f32-gate.py`. Two gates, two claims -- the constants here, the conversion there -- and
neither alone would have caught the other.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate

# The three rows whose OBVIOUS spelling measured wrong. They are pinned by NAME here, and
# their CONTENT is pinned by the value gate next door -- so a later "simplification" back to
# the more precise-looking literal is a gate failure and not a silent one-ulp regression
# nobody notices until a gelu output drifts.
GATE = Gate(
    "ew-consts-gate",
    bend="ew-consts.bend",
    oracle="ew-consts-oracle.py",
    rows=21,
    pins=[("py", "k_log10_2"), ("py", "k_selu_gamma"), ("py", "k_sqrt_2_over_pi"),
          ("py", "k_inv_log2"),
          ("bd", "k_log10_2"), ("bd", "k_selu_gamma"), ("bd", "k_sqrt_2_over_pi"),
          ("bd", "k_inv_log2")],
)

if __name__ == "__main__":
    ok = GATE.run() == 0
    print("ew-consts-gate: 21 rows, 3 lanes byte-identical" if ok else "ew-consts-gate: FAILED")
    sys.exit(0 if ok else 1)
