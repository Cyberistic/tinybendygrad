#!/usr/bin/env python3
"""uop_cast-gate.py -- THE GATE for `tinybendygrad/uop/ops.bend`'s `UOp.cast`.

    .venv/bin/python gates/uop_cast-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that the new `UOp.cast` (ops.bend:2783) does what CPython's `UOp.cast` (mixin/dtype.py:19)
does. The wall that lived at `tc_ptx.bend:408` ("needs `UOp.cast` (0 defs)") and the
related walls at `tc_ptx.bend:409-412` were closed by porting the def itself.

DEVIATION FROM CPYTHON. CPython's identity check reads `self.dtype`, which is a FOLD
property (ops.py:247 `dtype_from_uop`). A rule body that has no fold context cannot
read `self.dtype`, so the identity check is unreachable from a rule body. THE PORT
ALWAYS BUILDS A NEW NODE, which means: when `self.dtype` already equals `dt`, the
graph has ONE extra `OpsCAST{}` node that CPython would have skipped. The extra node
is a GRAPH BLOAT, not a correctness issue: the cast is a no-op on the value, and
downstream optimizations fold it. The full identity check would need a FOLD CONTEXT,
which is what `cast_at` in `mixin/dtype.bend:335` IS, and a future unit that wires
rule bodies into the fold can call THAT instead.

WHAT THIS IS FOR. `UOp.cast` was the SEAM for `pm_drop_after`-style rule bodies in
multi.bend and hcq2.bend, and for the bool LOAD/STORE/SHL/SHR rules in tc_ptx.bend.
Closing it means those 4-5 walls cite a `UOp.cast` that IS a def, and the only blocker
left is the FOLD the bodies also need (`y.dtype`, `idx.addrspace`, etc.).
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
    "cast_op_is_cast",            # .cast(dtype) sets op to CAST.
    "cast_src_is_input",          # .cast(dtype) sets srcs to (self,).
    "cast_arg_is_adt",            # .cast(dtype) sets arg to (dt,).
    "cast_builds_new_node",       # the result is a different node from the input.
    "cast_works_on_alu",          # .cast(dtype) on an ALU also sets op to CAST.
    "cast_is_reachable",          # the def is callable (the wall was 0 defs).
    "cast_does_not_mutate_input", # the input still has its original op.
    "cast_dedup_to_one_node",     # two .cast calls with the same input and dtype
                                  # dedup to ONE node (CPython's ucache interning).
)

GATE = Gate(
    "uop_cast-gate",
    bend="uop_cast.bend",
    oracle="uop_cast-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "uop_cast-gate: 8 rows, 3 lanes -- UOp.cast's op/src/arg set, "
                        "new-node build, ALU reachability, input purity and dedup all "
                        "agree with CPython (graph bloat when dtypes already match is "
                        "the documented DEVIATION)"))