#!/usr/bin/env python3
"""tc_ptx_types-gate.py -- the PTX dtype tables over every dtype a kernel can carry.

    .venv/bin/python gates/tc_ptx_types-gate.py

SIXTY ROWS, THREE LANES (CPython, bend interpreted, bend compiled), TWENTY-FOUR DECLARED
DIVERGENCES.

WHAT THIS IS FOR. `tinybendygrad/renderer/tc_ptx.bend`'s `types_pri` dispatched on
`S.Dt.pri` and had `case _: ""`. `pri` is unique over CPython's twelve KEYS and is NOT
unique over the dtypes a kernel can carry: MEASURED, pri 0 is `bool`, `void` AND
`weakint`, and pri 9 is `weakfloat`. So the table answered `pred` for `void` and
`weakint`, `u8` for `weakint` in `mem_types`, and `""` for `weakfloat` -- where
`PTXRenderer.types` raises `KeyError` on all three. `pred` and `u8` are CONCRETE PTX
types, so the kernel that came out was not rejected, it was WRONG: `renderer/amd/dsl.bend`'s
`U32.shln` shape, where a wrong value is smaller rather than absent. The empty field was
the LOUD half of the same bug and the wrong type was the quiet half, and the loud half is
what got reported.

THE TWENTY-FOUR DIVERGENCES ARE DERIVED, NOT WRITTEN DOWN, AND EVERY PIN IS CPYTHON'S.
For each dtype CPython raises on, the port's answer must be what `PTXRenderer.types` says
about `strong_dtype(dtype)` -- `dtype.py:169-170`, `{weakint: default_int, weakfloat:
default_float}`, which is CPython's OWN answer to "what does a weak dtype mean" -- and
`EMPTY` when even that raises. So `void`, the four fp8 and bf16 pin `EMPTY` and the two
weaks pin `s32`/`f32`, and NONE of those five strings is written in this file. Change
`DEFAULT_INT` and the pins move; make `strong_dtype` answer something else and they move.

WHAT A REVERT DOES. `gates/tc_ptx_types-mutate.py` puts the three-arm `cls` dispatch back
to a bare `types_pri(pri)` and reads SIX of the twenty-four pins move and the gate goes
red. That is the row that can fail; the 334 rows in `tc_ptx.bend`'s own table moved by
ZERO when the same fix landed, which is why the defect survived.
"""

import sys
from pathlib import Path

# Run with the repo's venv (`.venv/bin/python gates/tc_ptx_types-gate.py`): the pins below
# are computed FROM tinygrad rather than typed, which needs the venv's editable install and
# is the one thing this gate asks of its caller. The oracle lane does the same in its own
# process; nothing is shared between the two, which is the point of a two-lane gate.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main
from tinygrad.dtype import dtypes, strong_dtype
from tinygrad.renderer.ptx import PTXRenderer

TABLES = ("types", "mem_types", "cast_types")
POP = sorted([dtypes.void, *dtypes.all, *dtypes.weaks], key=lambda d: d.name)


def strong_or_empty(dtype):
    """THE POLICY, IN ONE LINE, AND IT IS ALL CPYTHON'S. What a dtype CPython's `types`
    does not have must resolve to the PTX type of `strong_dtype(dtype)` -- or to `EMPTY`,
    because `strong_dtype` leaves `void`, the fp8s and bf16 alone and `types` has no key
    for those either, so there is nothing honest to emit and a refusal is correct."""
    try:
        return PTXRenderer.types[strong_dtype(dtype)]
    except KeyError:
        return "EMPTY"


# DERIVED COUNTS. `ROWS` from the population the ORACLE found; `COMPARED` from the pins.
# A twenty-first dtype, a ninth miss or a lost row is one of these two moving.
DIVERGES = {f"{t}_{d.name}": (f"{t}_{d.name}=KeyError", f"{t}_{d.name}={strong_or_empty(d)}")
            for t in TABLES for d in POP if d not in PTXRenderer.types}
ROWS = len(TABLES) * len(POP)
COMPARED = ROWS - len(DIVERGES)

GATE = Gate(
    "tc_ptx_types",
    bend="gates/tc_ptx_types.bend",
    oracle="gates/tc_ptx_types-oracle.py",
    rows=ROWS,
    compared=COMPARED,
    diverges=DIVERGES,
)

if __name__ == "__main__":
    sys.exit(main(GATE, f"tc_ptx_types-gate: {ROWS} rows, 3 lanes, {len(DIVERGES)} pinned "
                        f"divergences -- every dtype CPython's `types` refuses resolves to "
                        f"`strong_dtype`'s PTX type or to EMPTY, never to a concrete wrong one"))