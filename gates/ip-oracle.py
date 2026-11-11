#!/usr/bin/env python3
"""ip-oracle.py -- the CPython lane for `gates/ip-gate.bend`.

    .venv/bin/python gates/ip-oracle.py

It prints `oracles/tinybendygrad_runtime_support_nv_ip.bend.rows` and nothing else.
Those 1,428 rows are upstream's own answer: the `.nv.info` / `.nv.constant` section
decoder run over the section blobs `nvdisasm` produced, plus the PCIe BAR
geometry read out of `tinygrad/runtime/autogen/nv.py`.

The rows are read by path rather than transcribed, because a transcription of
1,428 rows is 1,428 places to be wrong, and the tree has already measured that:
the `renderer/cstyle.bend` unit shipped 215 hand-typed expectations and
seventeen were wrong.
"""

import sys
from pathlib import Path

ROWS = (
    Path(__file__).resolve().parents[1]
    / "oracles"
    / "tinybendygrad_runtime_support_nv_ip.bend.rows"
)

if __name__ == "__main__":
    sys.stdout.write(ROWS.read_text())
