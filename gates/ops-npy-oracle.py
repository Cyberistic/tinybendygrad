#!/usr/bin/env python3
"""ops-npy-oracle.py -- the CPython lane for `gates/ops_npy-gate.bend`.

    .venv/bin/python gates/ops-npy-oracle.py

It prints `oracles/tinybendygrad_runtime_ops_npy.bend.rows` and nothing else, and
that is deliberate rather than lazy: those 83 rows ARE the CPython run. They were
taken by driving a real `NpyDevice('NPY')` through upstream's own code -- the
allocator's `_view`, the `HostAllocator` base, the four constructor arguments, the
peer/arch handshake -- and recorded under the name that says which port file they
belong to.

The generator that wrote them, `.agents/slop/oracle_npy_torch.py`, is gone: the
sweep at `371cc64c9` deleted it, and `git cat-file -e HEAD:<that path>` says the
path is absent from HEAD. Rather than transcribe its arithmetic into a second
copy, this lane reads the artifact by path, so the comparison stays against what
CPython actually printed. `oracles/README.md` describes the naming.
"""

import sys
from pathlib import Path

ROWS = Path(__file__).resolve().parents[1] / "oracles" / "tinybendygrad_runtime_ops_npy.bend.rows"

if __name__ == "__main__":
    sys.stdout.write(ROWS.read_text())
