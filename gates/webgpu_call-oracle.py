#!/usr/bin/env python3
"""webgpu_call-oracle.py -- the CPython lane for `gates/webgpu_call-gate.bend`.

    .venv/bin/python gates/webgpu_call-oracle.py

It prints `oracles/webgpu_call_rows.rows` and nothing else. Those 58 rows are a
recorded CPython run -- the constants read out of
`tinygrad/runtime/autogen/webgpu.py` -- and the file is read BY PATH so the
comparison is against what CPython printed and not against a second copy.
"""

import sys
from pathlib import Path

ROWS = Path(__file__).resolve().parents[1] / "oracles" / "webgpu_call_rows.rows"

if __name__ == "__main__":
    sys.stdout.write(ROWS.read_text())
