#!/usr/bin/env python3
"""mop_idxneg-gate.py -- THE GATE for Python's list index in `tinybendygrad/uop/movement.bend`.

    .venv/bin/python gates/mop_idxneg-gate.py

SIXTEEN ROWS, TWO LANES -- CPython and the port -- over ONE property: a STACK indexed by
a CONST's VALUE, and what a NEGATIVE value means.

THE DEFECT THIS GATE EXISTS FOR. `tinygrad/uop/movement.py`'s `mop_cleanup` rule 6 and
`tinygrad/uop/ops.py`'s `UOp.index` both spell the index as PYTHON'S LIST INDEX:

    `a.src[i.val] if len(idx.src) <= 2 else a.src[i.val].index(*idx.src[2:])` -- tinygrad/uop/movement.py:22
    `return self.src[new_srcs[0].val]` -- tinygrad/uop/ops.py:561

so a negative `i.val` reads from the END. The port read the index as a `U32`, so a negative
value became a huge `U32` and the answer was the FIRST element. MEASURED 2026-10-30, on
`UOp(Ops.INDEX, src=(STACK(CONST 3, CONST 5, CONST 7), CONST(-1)))`:

    upstream `mop_cleanup`   ->  UOp(Ops.CONST, arg=7)
    the port before the fix   ->  UOp(Ops.CONST, arg=3)

THE ROW IS THE VALUE, not the OP, and that is load-bearing: an OP row reads `CONST` on
both sides for the WRONG index and does not move, so it could not see this defect at all.

THE OUT-OF-RANGE ROWS ARE `none` ON BOTH SIDES, and they are not a divergence: CPython
raises `IndexError` and the port has no exception form, so the port's answer is "no
rewrite". `none` is the one spelling both sides can print.

THE TWO CALL SITES ARE SEPARATE ROWS on purpose. `mop_cleanup` rule 6 and `UOp.index` are
different functions that happen to index the same way, and a fix that covered one and not
the other would leave the corpus green and the port wrong.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = tuple(
  f"{site}_{tag}"
  for site in ("mcl", "uidx")
  for tag in ("neg1", "neg2", "neg3", "neg4", "pos0", "pos1", "pos2", "pos3")
)

GATE = Gate(
  "mop_idxneg-gate",
  bend="gates/mop_idxneg.bend",
  oracle="gates/mop_idxneg-oracle.py",
  rows=len(ROWS),
  pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
  sys.exit(main(GATE, "mop_idxneg-gate: 16 rows, 2 lanes -- Python's list index into a STACK, "
                      "over `mop_cleanup` rule 6 and `UOp.index`. A NEGATIVE index reads from "
                      "the END (`a.src[-1]` is the LAST element) and an out-of-range index is "
                      "upstream's `IndexError`, which the port spells 'no rewrite'"))
