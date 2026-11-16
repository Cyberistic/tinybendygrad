#!/usr/bin/env python3
"""webgpu_call-gate.py -- the gate for `tinybendygrad/runtime/webgpu_call.bend`.

    .venv/bin/python gates/webgpu_call-gate.py

58 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. `webgpu_call.py` is the WebGPU call layer: the enum values
come out of `tinygrad/runtime/autogen/webgpu.py` and the buffer-usage and
feature bits are read out of the same generated file. Every row is a NUMBER, and
a number that is wrong does not fail to compile -- so the rows are the numbers
and the oracle is the generated file.

THE ORACLE READS A RECORDED CPYTHON RUN BY PATH.
`oracles/webgpu_call_rows.rows` holds the 58 rows, and the oracle lane reads
that file rather than transcribing it: a transcription of 58 rows is 58 places
to be wrong, and this tree has measured that cost -- the `renderer/cstyle.bend`
unit shipped 215 hand-typed expectations and SEVENTEEN were wrong.

THE LANES ARE ALIGNED BY ROW NAME, and the order is not a claim here.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "webgpu_call-gate",
    bend="gates/webgpu_call-gate.bend",
    oracle="gates/webgpu_call-oracle.py",
    rows=58,
    compared=58,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "webgpu_call-gate: 58 rows compared -- the WebGPU enum "
                        "values agree with the CPython run"))
