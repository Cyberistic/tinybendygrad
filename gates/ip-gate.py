#!/usr/bin/env python3
"""ip-gate.py -- the gate for `tinybendygrad/runtime/support/nv/ip.bend`.

    .venv/bin/python gates/ip-gate.py

1,428 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. `ip.py` is a pure decoder: it takes the `.nv.info` and
`.nv.constant0.*` section bytes a compiled kernel carries, and answers the
register layout, the shared-memory window, the parameter slots and the launch
geometry. Every one of those is arithmetic over bytes the caller supplies, so
every one is a row -- there is no drive to stand in front of this file and
nothing in it is a runtime race.

THE ROWS ARE GROUPED BY RULE AND THE ORACLE BY SOURCE ORDER, so the lanes are
aligned by row name (`order="by_name"`). What that costs is stated in
`gatekit.py`: a by-name diff cannot see a row that MOVED. The order is not a
claim here; the claims are the layouts, and a layout is one row whose value is a
comma-separated field list.

THE ORACLE IS A RECORDED CPYTHON RUN. `gates/ip-oracle.py` prints
`oracles/tinybendygrad_runtime_support_nv_ip.bend.rows`, which upstream's decoder
produced over the section blobs `nvdisasm` emitted. Nothing in the driver is
typed by hand.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "ip-gate",
    bend="gates/ip-gate.bend",
    oracle="gates/ip-oracle.py",
    rows=1428,
    compared=1428,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "ip-gate: 1428 rows compared -- the nv section decoder "
                        "agrees with the CPython run"))
