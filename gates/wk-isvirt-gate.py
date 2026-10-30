#!/usr/bin/env python3
"""wk-isvirt-gate.py -- THE GATE for `wk_is_virtual` (uop/weak.bend), ops.py:902.

    .venv/bin/python gates/wk-isvirt-gate.py

FIVE ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- 5 IDENTICAL.

WHAT IS UNDER TEST. `tinygrad/uop/ops.py:902` is ONE line:

    return self.device is None or self.dtype in dtypes.weaks

and the port spells it as TWO claims joined by `or` (`uop/weak.bend:268`): the device
half and the dtype half. The device half is a NESTED `Maybe` -- the outer answers "does
this node carry a device at all" and the inner "is it there" -- and flattening them
first would lose the one case `is_virtual` asks about.

WHY THIS GATE EXISTS, AND THE REASON IS A STALE CLAIM THAT WAS MEASURED. `uop/ops.bend:5345`
says of `wk_is_virtual`:

    PORTED BUT UNGATED, AND THE REASON IS A FIXTURE, NOT A DEF. `is_virtual` answers
    `device is None or dtype in weaks`, and the device half needs a node that CARRIES a `Dev`:
    `fold.bend`'s `mw_pa` hard-codes `ParamArg`'s device field to `None{}` and no def in the
    port sets it, so EVERY node is virtual and the reader has no negative witness. MEASURED:
    both candidate rows came out `True`, and two rows that are always `True` cannot fail.

THAT REASON IS FALSE TODAY. MEASURED 2026-10-30: `renderer/__init__.bend:450` builds a
`ParamArg` with `device = Some{S.D1{0}}`, and `fold.bend`'s `device_of.param` reads
`O.ParamArg.device(pa)` -- so a node that CARRIES a device is reachable and
`wk_is_virtual` has a negative witness for the first time. This gate is that witness.

THE FIVE CELLS ARE A CROSS of two independent questions, so a reader that answered one
of them correctly BY ACCIDENT cannot pass all five:

              device PRESENT        device ABSENT
  strong dtype   False                True
  weak dtype     True                 True

The two `True` cells on the WEAK row are the point: a reader that only asked the DEVICE
question would answer `False` for a weak node that carries a device, and a reader that
only asked the DTYPE question would answer `False` for a strong node without one. Only
the disjunction answers all five, and only the disjunction is `ops.py:902`.

THE ROW THAT FAILS IF THE DEVICE IS IGNORED IS THE FIRST ONE, and the row that fails if
the DTYPE is ignored is the SECOND, so neither half can be dropped without a row moving.
The fifth row is a second strong dtype, so the `False` cell is not a fact about int32
alone.

MUTATIONS, and each one is MEASURED to move the row it names:
  1 `wk_is_virtual` drops the device half            iv_nodev_strong          (1 of 5)
  2 `wk_is_virtual` drops the dtype half             iv_dev_weakint           (1 of 5)
  3 `wk_is_virtual` returns the AND of the halves    iv_dev_weakint, iv_nodev_strong  (2 of 5)

Each mutation was applied to `tinybendygrad/uop/weak.bend`, the gate was re-run, and the
port was restored; all three go rc=1 FAIL with the rows named, and the restored file is
byte-identical to HEAD. A gate whose mutations move NOTHING is a label.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = ("iv_dev_strong", "iv_dev_weakint", "iv_nodev_strong", "iv_nodev_weakint", "iv_dev_single")

GATE = Gate(
    "wk-isvirt-gate",
    bend="wk-isvirt.bend",
    oracle="wk-isvirt-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "wk-isvirt-gate: 5 rows, 3 lanes, 0 documented divergences -- "
                        "`is_virtual` is `device is None or dtype in weaks`, and the DEVICE "
                        "half has a negative witness for the first time (`renderer/__init__.bend:450` "
                        "builds a ParamArg that CARRIES a Dev, which is what `uop/ops.bend:5345` "
                        "said no def in the port did)"))
