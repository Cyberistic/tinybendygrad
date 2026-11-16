#!/usr/bin/env python3
"""torch-oracle.py -- the CPython lane for `gates/torch-gate.bend`.

    .venv/bin/python gates/torch-oracle.py

It prints `oracles/tinybendygrad_nn_torch.bend.rows` and nothing else. Those 45
rows are a recorded CPython run of the port's own fixtures through `os.path`, and
the file is read BY PATH so the comparison is against what CPython printed and
not against a second copy of it.
"""

import sys
from pathlib import Path

ROWS = Path(__file__).resolve().parents[1] / "oracles" / "tinybendygrad_nn_torch.bend.rows"

if __name__ == "__main__":
    sys.stdout.write(ROWS.read_text())
