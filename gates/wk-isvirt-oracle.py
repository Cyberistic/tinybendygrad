#!/usr/bin/env python3
"""wk-isvirt-oracle.py -- CPython's answers to `gates/wk-isvirt.bend`'s five rows.

    .venv/bin/python gates/wk-isvirt-oracle.py

WHAT IS UNDER TEST. `tinygrad/uop/ops.py:902` is ONE line:

    return self.device is None or self.dtype in dtypes.weaks

and the port spells it as two claims joined by `or` (`uop/weak.bend:268`): the device
half and the dtype half. The device half is a NESTED `Maybe` -- the outer answers "does
this node carry a device at all" and the inner "is it there" -- and flattening them
first would lose the one case `is_virtual` asks about.

THE FIVE CELLS ARE A CROSS of two independent questions, so a reader that answered one
of them correctly by accident cannot pass all five:

              device PRESENT        device ABSENT
  strong dtype   False                True
  weak dtype     True                 True

The two `True` cells on the WEAK row are the point: a reader that only asked the DEVICE
question would answer `False` for a weak node that carries a device, and a reader that
only asked the DTYPE question would answer `False` for a strong node without one. Only
the disjunction answers all five, and only the disjunction is `ops.py:902`.

THE DEVICE IS SET ON THE PARAM'S OWN ARG, which is where upstream keeps it:
`ParamArg.device`. Upstream's `UOp.param` takes `device=None` by default and stores it
in the arg, and `UOp.device` reads it back. So the fixture sets the FIELD, not a
wrapper -- a reader that read the device from the wrong place would answer `True` on
every row and be caught by `iv_dev_strong`.

THE FIXTURE IS BUILT WITH UPSTREAM'S OWN `UOp.param`, for the reason
`wk-eval-oracle.py` records: a hand-built `UOp(Ops.PARAM, src=(), ...)` is a MALFORMED
PARAM -- upstream's `_shape` reads `self.src[0].as_shape` unguarded -- and `_eval` dies
inside `simplify()`. Here it does not reach `_eval`, but the same builder is the one
upstream's own code uses, so the lane does not depend on a fixture shape upstream
cannot handle.
"""

import sys
from dataclasses import replace

from tinygrad import dtypes
from tinygrad.uop.ops import UOp


def param(dt, device):
    """A PARAM carrying an explicit dtype and an explicit device, as upstream's `UOp.param` does.

    A WEAK dtype needs `replace` rather than `UOp.param`, because upstream REFUSES to build
    one: `ops.py:1223` raises `RuntimeError(f"cannot create param for weak dtype {dtype}")`.
    The refusal is upstream's own and it is a fact about `UOp.param`, not about `is_virtual`:
    a weak-dtype node that CARRIES a device is still a legal node for `is_virtual` to answer,
    and it is the only cell that separates the two halves of the `or`. `replace` on the arg
    keeps the PARAM's src, so the node stays well-formed.
    """
    p = UOp.param(0, dtypes.int32, device=device)
    return p.replace(arg=replace(p.arg, dtype=dt)) if dt is not dtypes.int32 else p


def is_virtual(u: UOp) -> bool:
    """`ops.py:902` VERBATIM, so the lane cannot drift from the reference."""
    return u.device is None or u.dtype in dtypes.weaks


# (row, dtype, device) -- `device=None` is upstream's "no device", and `device="CPU"` is
# a device NAME, which is what a PARAM carries.
CASES = [
    ("iv_dev_strong", dtypes.int32, "CPU"),
    ("iv_dev_weakint", dtypes.weakint, "CPU"),
    ("iv_nodev_strong", dtypes.int32, None),
    ("iv_nodev_weakint", dtypes.weakint, None),
    ("iv_dev_single", dtypes.float32, "CPU"),
]


def main() -> None:
    for nm, dt, dev in CASES:
        # `str(True)` is `"True"` -- the port's `Bool.show` prints `"True"` too, so a Bool row
        # is TEXT on both sides and the diff is on the VALUE.
        print(f"{nm}={'True' if is_virtual(param(dt, dev)) else 'False'}")


if __name__ == "__main__":
    main()
