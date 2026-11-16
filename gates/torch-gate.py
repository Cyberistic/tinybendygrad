#!/usr/bin/env python3
"""torch-gate.py -- the gate for `tinybendygrad/nn/torch.bend`.

    .venv/bin/python gates/torch-gate.py

45 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. `torch.py` is a PATH resolver: it answers "where is the
package root" for a given path, and the port's rows are the four shapes that
distinguish the answers -- a relative path, an absolute path, a deep path and a
rooted path. Every one of them is a claim about `os.path`, and `os.path` is
CPython's own code.

THE ORACLE READS A RECORDED CPYTHON RUN BY PATH. `oracles/tinybendygrad_nn_torch.bend.rows`
holds the 45 rows CPython printed, and the oracle lane reads that file rather
than transcribing it: a transcription of 45 rows is 45 places to be wrong, and
this tree has measured that cost -- the `renderer/cstyle.bend` unit shipped 215
hand-typed expectations and SEVENTEEN were wrong.

THE LANES ARE ALIGNED BY ROW NAME, and the order is not a claim: the port groups
its rows by fixture and the oracle prints them in one sequence.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "torch-gate",
    bend="gates/torch-gate.bend",
    oracle="gates/torch-oracle.py",
    rows=45,
    compared=45,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "torch-gate: 45 rows compared -- the path resolver agrees "
                        "with the CPython run"))
