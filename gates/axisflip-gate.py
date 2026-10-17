#!/usr/bin/env python3
"""axisflip-gate.py -- `Tensor.flip`'s SHAPE, per axis, against CPython, on a base that can see
the axis.

    .venv/bin/python gates/axisflip-gate.py

NINE ROWS AND ONE CLAIM: for every axis of a rank-4 base whose dims are NOT all equal, the port's
`mxw_flip` returns the same shape CPython's `Tensor.flip` does. `gates/groupflip.bend` already
certifies the TOPOSORT of `flip` -- but on `mxw_reshape(mxw_base(), [4,4,4,4])`, where all four
dims are 4, and the defect this gate exists for is a substitution that is the IDENTITY whenever
`shape[0] == shape[axis]`. This gate's base is `(2,4,4,8)`.

WHY A SHAPE AND NOT A TOPOSORT, AS A MEASUREMENT. `<OP>x<nsrc>[<src ops>]{order}` -- the row
`groupflip` compares -- carries the op, the src count, the src op SEQUENCE and the PERMUTE order,
and it carries no RESHAPE target shape, no PAD offset and no SHRINK size. The defect was a wrong
`crop`/`tail` LIST, so it moved exactly those. MEASURED across the fix: `mxw_flip`'s node count,
its root op, its src count and its src op SEQUENCE were all BYTE-IDENTICAL while the shape went
`(4,4,8,8)` -> `(1,4,8,8)`. A graph row cannot see a wrong shape, so the row that can is the one
carrying the size. `n=` rides along because it is the axis-SENSITIVE half -- CPython's counts here
are 10 / 28 / 37 / 37 / 37 / 52 / 52, so the oracle lane is seven distinct measurements rather
than one answer repeated seven times.

THE `axis1` ROW IS THE BLINDNESS GUARD AND IT IS A COMPARED ROW, NOT A COMMENT. It prints
`base.shape[1:]` against `base.transpose(0, 1).shape[1:]` -- the two lists the defect is about --
so a base on which they are equal turns this gate RED while leaving every other row green. On this
base they read `4,4,8` against `2,4,8`; on (4,4,4,4) they read `4,4,4` against `4,4,4`. That is the
whole answer to "what would it take to make a flip gate able to see the axis", and it is a base
choice plus a row that carries a size; a gate on (4,4,4,4) has neither.

WHAT THIS GATE DOES NOT CLAIM. It does not claim the VALUES are right -- `flip` reverses a tensor
and this gate never reads one element -- and it does not claim the node sequence is right, which is
`gates/groupflip-gate.py`'s eleven rows on its own base. It claims the SHAPE, which is the half of
`flip` that the toposort row provably cannot see. Zero declared divergences, and the three lanes
are the same three `gatekit` runs.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

# THE NINE ROWS, in the driver's own order: the base, the empty axis list, one axis each, two
# axes in each order, and the blindness guard. `gatekit` refuses the run if a lane disagrees with
# this count, so the count is a MEASUREMENT of the lanes and not a typed inventory.
ROWS = ("base", "fnone", "f0", "f1", "f2", "f3", "f01", "f10", "axis1")

# ZERO DECLARED DIVERGENCES. All nine rows are COMPARED rows, and this gate was written after the
# fix it measures, so a divergence here would be the gate disagreeing with CPython rather than a
# known gap being pinned. The two upstream behaviours still not ported -- `_resolve_dim`'s negative
# axes (`movement.py:249`) and the `dedup` refusal (`:251`) -- are named in
# `tinybendygrad/mixin/movement.bend`'s flip header and NEITHER is reachable from these rows: every
# axis here is a non-negative in range and every axis list is distinct.
DIVERGING = ()

GATE = Gate(
  "axisflip-gate",
  bend="axisflip.bend",
  oracle="axisflip-oracle.py",
  rows=len(ROWS),
  compared=len(ROWS) - len(DIVERGING),
  diverges={},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def main() -> int:
  return gate(GATE,
              f"axisflip-gate: PASS -- {len(ROWS)} rows compared exactly on a (2,4,4,8) base, "
              "0 declared divergences; the witness is the SHAPE of `Tensor.flip` per axis "
              "(movement.py:233-267), which a `<OP>x<nsrc>[srcs]{order}` row cannot carry, and "
              "`axis1` is the row that says this base can see the axis at all",
              )


if __name__ == "__main__":
  sys.exit(main())