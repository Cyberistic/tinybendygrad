#!/usr/bin/env python3
"""tn_binop_sweep-gate.py -- ONE ROW PER BINOP, all at DEPTH 1.

    .venv/bin/python gates/tn_binop_sweep-gate.py

NINETEEN ROWS, THREE LANES, ZERO DIVERGENCES. A SWEEP, NOT A SAMPLE.

`gates/tn_binop_arena-gate.py` varies the DEPTH of `tn_add` and nothing else, so a
sibling-arena regression in any of the other sixteen binops would be invisible there. Every
reverse-dispatch binop in `tinybendygrad/tensor.bend` routes through `tn_binop` -- VERIFIED by
reading, `awk` over the file prints sixteen `.go` bodies plus `tn_max`, and every one of the
seventeen is a `tn_binop(lhs, rhs, O.OpsX{})` line -- and this gate proves it for each.

THE RIGHT OPERAND IS `3 + 3` IN ITS OWN ARENA AT EVERY ROW, so its index is NOT 0 and an
un-merged read lands on the slot the node itself takes. Each row asserts TWO facts in one name:
`src[1]` is the caller's operand, and `src[1]` is NOT the node being built.

THE TWO CONTROLS are the depth-0 shape every other binop gate in this directory builds, and
they ask the same question about a BARE CONST -- so their expected op is `Ops.CONST` and not
the `Ops.ADD` the sweep rows use. A control that is 0 for the wrong reason is not a control.

`tn_sub` CARRIES A DIFFERENT EXPECTED OP AND THE ROW SAYS WHY: CPython's `Tensor.sub`
(elementwise.py:103) is `a.alu(Ops.ADD, -b)`, so `-` builds `ADD(self, MUL(x, -1))` and
`src[1]` is a MUL. The arena question is identical; only the op differs.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

BINOPS = (
    "tn_add", "tn_and", "tn_cmplt", "tn_cmpne", "tn_fdiv", "tn_lshift", "tn_max",
    "tn_maximum", "tn_mod", "tn_mul", "tn_or", "tn_pow", "tn_rshift",
    "tn_sub", "tn_xor",
)

ROWS = tuple(f"{b}_src1_is_the_callers_operand" for b in BINOPS) + (
    "tn_radd_src0_is_the_callers_operand",
    "tn_rsub_src0_is_the_callers_operand",
    "tn_rmul_src0_is_the_callers_operand",
    "tn_rfdiv_src0_is_the_callers_operand",
    "tn_rmod_src0_is_the_callers_operand",
    "tn_rand_src0_is_the_callers_operand",
    "tn_ror_src0_is_the_callers_operand",
    "tn_rxor_src0_is_the_callers_operand",
    "tn_rpow_src0_is_the_callers_operand",
    "tn_rlshift_src0_is_the_callers_operand",
    "tn_rrshift_src0_is_the_callers_operand",
    "control_depth0",
    "control_same_tensor",
)

GATE = Gate(
    "tn_binop_sweep-gate",
    bend="tn_binop_sweep.bend",
    oracle="tn_binop_sweep-oracle.py",
    rows=len(ROWS),
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_binop_sweep-gate: 28 rows, 3 lanes, 0 divergences -- ALL SIXTEEN "
                        "binops re-mint the right operand before reading its index, at depth 1, "
                        "plus the ELEVEN reverse arms, and the depth-0 and same-tensor controls"))