#!/usr/bin/env python3
"""target-roundtrip-gate.py -- THE ROUND TRIP: a parsed `Target` goes into a
`ProgramInfo` and comes back unchanged.

    .venv/bin/python gates/target-roundtrip-gate.py

TWENTY ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- and the
row is a ROUND TRIP, not a parse. `<dev> => <before> -> <after>`, where `before`
is `Target.parse(s)` and `after` is the record read back out of a `ProgramInfo`.

WHY THE ROW CARRIES BOTH HALVES. Upstream has ONE `Target`
(`tinygrad/helpers.py:198`) and upstream's `uop/ops.py:13` and
`runtime/ops_python.py:9` both IMPORT it from there. The port had TWO records
with the same five fields and DIFFERENT identities, so a parsed `Target` could
not go into a `ProgramInfo` at all -- and that was the test that was impossible.
A conversion that DROPS a field shows as `a|b|c|d| -> a|b|c||` and a conversion
that SWAPS `arch` and `iface` shows as `AMD|LLVM|gfx1100|usb|1 ->
AMD|LLVM|usb|gfx1100|1`. BOTH ARE SILENT in a row that prints only the parsed
target, because the five field NAMES are the same either way and only the ORDER
of the values differs. So the row carries both halves, and the ORACLE is
CPython's own `Target.parse` and CPython's own `ProgramInfo` -- called, never
re-implemented.

THE TWO LANES' DRIVERS. `gates/target-roundtrip.bend` is the Bend lane and it
reaches everything through `H.` and `O.`, so a mutation of `helpers.bend` or of
`uop/ops.bend` moves these rows. `gates/target-oracle.py` is the CPython lane.

RED, RIGHT NOW, FOR A REASON THAT IS NOT THIS GATE'S: `tinybendygrad/uop/ops.bend`
does not compile -- its `ProgramInfo.launch_dims` returns `(A, B)`, which is a
Sigma VALUE and not a Type, where Bend's product type is `A & B` -- and it also
still declares its OWN `Target`, so the round trip cannot be typed until that
record is replaced by `H.Target`. `gates/target-census-gate.py` names both.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. The same twenty the oracle walks, in the same order.
ROWS = (
    "target-empty",
    "target-device-only",
    "target-device-renderer",
    "target-device-renderer-arch",
    "target-arch-not-uppercased",
    "target-lowercase-uppercased",
    "target-plus-interface",
    "target-plus-interface-indices",
    "target-plus-then-device",
    "target-interface-own-colon",
    "target-lower-interface-arch",
    "target-too-many-colons-refused",
    "target-too-many-pluses-refused",
    "target-interface-colons-not-budget",
    "target-device-three-fields",
    "target-device-four-fields-refused",
    "target-colon-only",
    "target-device-colon",
    "target-two-colons",
    "target-empty-middle-field",
)

GATE = Gate(
    "target-roundtrip-gate",
    bend="target-roundtrip.bend",
    oracle="target-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "target-roundtrip-gate: 20 rows, 3 lanes -- a parsed `Target` goes "
                        "into a `ProgramInfo` and comes back with the same five values, in "
                        "the same order, and the two halves of every row are the claim"))
