#!/usr/bin/env python3
"""paramarg-shape-oracle.py -- WHERE UPSTREAM PUTS A BUFFER/PARAM'S SIZE.

    .venv/bin/python gates/paramarg-shape-oracle.py

WRITTEN AGAINST UPSTREAM, AND THAT IS THE WHOLE POINT. The port disagrees with these
rows today, and the port is what is wrong: `gates/paramarg-shape-gate.py`'s header
says why, and this file names no port value. **DO NOT ADD A `diverges` CARVE-OUT TO
MAKE THIS FILE AGREE WITH THE PORT.** A carve-out would make the two lanes say the
same thing by deleting one of the answers, which is the `DEAD`-instrument failure with
a green exit status.

THE SIZE IS IN `src[0]` AND NOT IN `ParamArg`, AND THIS FILE USES UPSTREAM'S OWN
CONSTRUCTORS RATHER THAN SPELLING ONE. `UOp._buffer` (`ops.py:828-830`) builds
`src=(shape_to_shape_arg((size,)),)+UOp.device_range_src(device)` and passes
`ParamArg(slot, dtype, addrspace=..., device=..., buffer=...)` with no size at all;
the field was DELETED upstream (72f98ffe0, "move size from ParamArg to src (#18624)").
`UOp._shape`'s BUFFER arm (`ops.py:355-357`) then reads `self.src[0].as_shape`.

THE SCALAR ROW IS THE ONE PLACE THE TWO CONSTRUCTORS DIFFER, and the split is
upstream's own: `_buffer` has no scalar arm (it takes `size: int`), so the `None`
row is `UOp.param(0, dt, None)`, whose `ops.py:1222` builds
`src=(shape_to_shape_arg(()),)` -- a `UOp(Ops.STACK)` with no srcs of its own, so
the PARAM carries `nsrc=1` and the STACK carries `nsrc=0`. `shape_to_shape_arg(())`
is NOT `shape_to_shape_arg((0,))` and the two `pa_shape_none` / `pa_shape_0` rows
are what say so.

WHY `nsrc` IS A ROW. The size is CORRECT in both lanes -- `pa_shape_4` is `(4)` on
both -- so a gate on shape alone is green over a port that encodes the size in the
wrong place. `nsrc` is the encoding, and it is the only field of these six rows that
disagrees. That is the finding, and it is why this file emits it rather than a
comment about it.
"""
from __future__ import annotations

from tinygrad import dtypes
from tinygrad.uop.ops import UOp


def shape_of(u: UOp) -> str:
  """`_shape` rendered the way `F.dims_str` renders it (`fold.bend:5817`): `(` joined
  `)`, NO trailing comma, so the two lanes' spelling is the same string."""
  s = u._shape
  return "none" if s is None else "(" + ",".join(str(x) for x in s) + ")"


def row(nm: str, u: UOp) -> None:
  print(f"{nm}={shape_of(u)} nsrc={len(u.src)}")


def scalar() -> UOp:
  return UOp.param(0, dtypes.float, None)


def buf(size: int) -> UOp:
  return UOp._buffer(size, dtypes.float, 0)


def main() -> None:
  row("pa_shape_none", scalar())
  for n in (0, 1, 4, 6):
    row(f"pa_shape_{n}", buf(n))
  # IDENTITY, asked of the interning cache and not of two hand-made nodes. A UOp is
  # hash-consed on (op, src, arg), so the size is in the key only if it is in `src` or
  # in `arg`; `gates/paramarg_shape.bend` asks the same question of the port's Arena.
  print(f"pa_reintern_4_4={buf(4) is buf(4)} pa_reintern_0_1={buf(0) is buf(0)} "
        f"pa_distinct_4_6={buf(4) is buf(6)} pa_distinct_0_1={buf(0) is buf(1)}")


if __name__ == "__main__":
  main()