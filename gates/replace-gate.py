#!/usr/bin/env python3
"""replace-gate.py -- THE GATE for `tinybendygrad/uop/ops.bend`'s `UOp.replace`.

    .venv/bin/python gates/replace-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `UOp.replace` does what CPython's `UOp.replace` does. The wall that lived at
`function.bend:1084` ("UOp.replace -- `ParamArg` is a 13-field Data record ... a builder
with no caller is a lie") was closed by porting the def itself: 8 callers (`ptx.py:49,52`,
`pm_replace_buffers` at hcq2.py:103, and the bodies behind the `UOp.replace` calls in
`pm_unwrap_multi`/`pm_lift_deps`) now have a def to resolve to, and this gate is the
denominator that proves the port matches CPython on each property.

WHAT THIS IS FOR. `UOp.replace` is the seam ABOVE `substitute` (ops.py:532 -- the matcher-
driven form) and BELOW the per-field `ParamArg` constructor: a rule body that needs to
swap one or two fields of a node without rebuilding the rest calls it. The eight rows
cover identity (the no-op case), single-field swap, two-field swap, multi-src swap, and
the "did the new op actually change" check. A port that always built a new node would
fail the first row; a port that always returned identity would fail the rest.

WHY THIS GATE INSTEAD OF ANOTHER IN-FILE `t_*` TEST. The `t_*` cluster in `ops.bend`
already tests CONST identity (32 rows in `ops-core-gate.py`), and those are the rows the
project's own notes say are "MEASURED on the live tree". `UOp.replace` is a different
property -- the constructor's behaviour under field swap -- and the wall text at
`function.bend:1084` was the project's admission that it had no row to back the
"DONE" claim, so the cheapest honest answer was a gate.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. The row NAME is the claim being asked, so it is pinned on both
# lanes: a row renamed on one lane only is a gate that stopped asking its question
# without saying so, and a value diff cannot see that at all -- same value, same verdict,
# different question.
ROWS = (
    "identity_returns_self",         # replace() with no kwargs returns the SAME UOp.
    "replace_op_sets_op",            # replace(op=Ops.ADD) sets the op to ADD.
    "replace_src_sets_srcs",         # replace(src=(c,)) sets srcs to (c,).
    "replace_arg_sets_arg",          # replace(arg=None) sets the arg.
    "replace_tag_sets_tag",          # replace(tag=True) sets the tag.
    "replace_src_two_elements",      # replace(src=(b,a)) sets srcs to (b,a) (reversed).
    "replace_op_actually_changes_op", # the new op is NOT the original op.
    "replace_arg_to_anone",          # replace(arg=None) on a CONST with arg=ConstInt sets arg=None.
)

GATE = Gate(
    "replace-gate",
    bend="replace.bend",
    oracle="replace-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "replace-gate: 8 rows, 3 lanes -- UOp.replace's identity, single-field "
                        "swap, two-field swap, multi-src swap, and the change-detection row "
                        "all agree with CPython"))
