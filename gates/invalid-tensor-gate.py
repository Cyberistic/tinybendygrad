#!/usr/bin/env python3
"""invalid-tensor-gate.py -- THE GATE FOR upstream `test/null/test_invalid_tensor.py`.

    .venv/bin/python gates/invalid-tensor-gate.py

19 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- over the property upstream's
`test_uop_where_keeps_invalid_bare` asserts.

THE PROPERTY. upstream `test/null/test_invalid_tensor.py` builds

    cond = UOp.const(0) < UOp.const(1)
    idx  = UOp(Ops.STACK, src=tuple(UOp.const(x) for x in range(3)))
    out  = cond.where(idx, UOp.invalid())

and asserts five things: the condition is a `CMPLT`, the stack is a `STACK`, the select is a
`WHERE`, the select's THIRD SRC is a **BARE CONST** (not a CAST, not an EXPAND), and that third
src is **STILL INVALID** after the WHERE.

⇒ AND THE FIFTH IS THE ONE THE TEST IS NAMED FOR: A WHERE THAT FOLDED THE INVALID AWAY, OR
  RE-SPELLED IT AS A CAST, WOULD PASS THE FOURTH ROW AND FAIL THE FIFTH. A GATE THAT ONLY
  ASSERTED THE OP OF `out.src[2]` WOULD PASS ON A WHERE THAT DROPPED THE INVALID ALTOGETHER.

WHY NOT `gates/ops-core`'s `valid_*` ROWS. THOSE ASK `cond.where(self, self.const_like(Invalid))`
-- A CONST `self` -- AND ANSWER THE **ARG** CLASS OF EACH SRC (`sg_ctor`). THIS TEST ASKS A
DIFFERENT QUESTION OF A DIFFERENT GRAPH: THE `x` IS A **STACK** WITH THREE SRCS, THE `y` IS A
**BARE INVALID CONST** RATHER THAN A `const_like` OF A SHAPED NODE, AND THE CLAIM IS ABOUT
**`out.src[2].op` AND `out.src[2].is_invalid`** -- WHICH NO `sg_ctor` ROW CAN SEE, BECAUSE
`sg_ctor` READS THE ARG AND NOT THE OP.

THE ROW NAMES ARE PINNED ON BOTH LANES AND THE VALUES ARE DIFFED AND NEVER PINNED: THE VALUE IS
THE CLAIM, AND PINNING IT HERE AS WELL WOULD PIN THE ANSWER TWICE OVER, WHICH IS HOW THE TWO
COPIES DRIFT APART.

NO ROW IS TRANSCRIBED FROM UPSTREAM's TEST. The oracle BUILDS THE SAME GRAPH IN CPython's OWN
`tinygrad` AND ANSWERS THE SAME QUESTIONS, so a row is a comparison of two implementations of
the property rather than a comparison of the port against a number somebody typed.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. THE ORDER IS THE ORDER BOTH LANES PRINT IN, AND THE GATE COMPARES THEM
# **POSITIONALLY** (`gates/gatekit.py`: `zip(base, other)`), SO THE ORDER IS PART OF THE
# CONTRACT.
ROWS = (
    # THE CONDITION -- `UOp.const(0) < UOp.const(1)` IS A `CMPLT` OVER TWO CONST SRCS, AND THE
    # ORDER IS CPython's: `_binop(Ops.CMPLT, x, False)` PUTS `self` AT `src[0]`.
    "cond_op", "cond_nsrc", "cond_src0_op", "cond_src1_op",
    # THE STACK -- A **RAW** STACK WITH THREE CONST SRCS. NOT `UOp.group`, WHICH AT THE PIN IS
    # `UOp(Ops.STACK).after(*srcs)` AND IS THEREFORE AN `AFTER`.
    "idx_op", "idx_nsrc", "idx_src0_op", "idx_src1_op", "idx_src2_op",
    # THE INVALID, BEFORE ANY WHERE TOUCHES IT.
    "inv_op", "inv_is_invalid",
    # THE WHERE, AND ITS THREE SRCS IN CPython's ORDER: `(cond, x, y)`.
    "out_op", "out_nsrc", "out_src0_op", "out_src1_op", "out_src2_op",
    # ⇒ THE PROPERTY THE TEST IS NAMED FOR.
    "out_src2_is_invalid",
    # AND THE SRCS SURVIVE BY IDENTITY: upstream's `_broadcasted` leaves a weakint STACK alone
    # and short-circuits the invalid, so NOTHING is cast or replaced.
    "out_src0_is_cond", "out_src1_is_idx",
)

GATE = Gate(
    "invalid-tensor-gate",
    bend="invalid-tensor.bend",
    oracle="invalid-tensor-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "invalid-tensor-gate: 19 rows, 3 lanes -- the WHERE keeps the invalid "
                        "BARE: a CONST, and still invalid, and the whole nodes survive by "
                        "identity"))
