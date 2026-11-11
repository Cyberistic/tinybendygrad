#!/usr/bin/env python3
"""ops-npy-gate.py -- the gate for `tinybendygrad/runtime/ops_npy.bend`.

    .venv/bin/python gates/ops-npy-gate.py

83 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. The port's allocator is the `HostAllocator` base with ONE
override, and the rows are the places where upstream's answer is arithmetic
rather than a device's: the view length (exactly `size` bytes, not a page, which
is what separates it from `BNXTAllocator._alloc`'s `round_up(mem.nbytes, 0x1000)`),
the DID stack, the peer/arch handshake, and the four constructor arguments.

WHY THERE IS NO GONE-DRIVE RULE HERE. `NpyDevice` opens no hardware, so every row
in the driver has a CPython counterpart; `port_only` is empty and the two lanes
have the same 83 names.

THE ORACLE IS A RECORDED RUN, AND THAT IS THE HONEST FORM FOR THIS ONE.
`gates/ops-npy-oracle.py` prints `oracles/tinybendygrad_runtime_ops_npy.bend.rows`,
which a real `NpyDevice('NPY')` produced. Its generator was deleted from the tree
by the sweep at `371cc64c9`; the artifact survived because a gate named it. A gate
that re-derived the rows from a re-written formula would be comparing the port to
a second copy of the port.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "ops-npy-gate",
    bend="gates/ops_npy-gate.bend",
    oracle="gates/ops-npy-oracle.py",
    rows=83,
    compared=83,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "ops-npy-gate: 83 rows compared -- the NPY backend's "
                        "allocator and handshake agree with the CPython run"))
