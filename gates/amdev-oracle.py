#!/usr/bin/env python3
"""amdev-oracle.py -- the CPython lane for `gates/amdev-gate.bend`.

    .venv/bin/python gates/amdev-oracle.py

It prints `oracles/tinybendygrad_runtime_support_am_amdev.bend.rows` and nothing
else. Those 564 rows are a recorded CPython run, and the file is read BY PATH so
the comparison is against what CPython printed and not against a second copy.
"""

import sys
from pathlib import Path

ROWS = (Path(__file__).resolve().parents[1] / "oracles"
        / "tinybendygrad_runtime_support_am_amdev.bend.rows")

if __name__ == "__main__":
    sys.stdout.write(ROWS.read_text())
