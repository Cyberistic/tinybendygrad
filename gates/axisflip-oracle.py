#!/usr/bin/env python3
"""axisflip-oracle.py -- CPython's `Tensor.flip` SHAPE and node count, PER AXIS.

    .venv/bin/python gates/axisflip-oracle.py

EIGHT ROWS, THE SAME EIGHT `gates/axisflip.bend` PRINTS, FROM CPYTHON: `base`, `fnone`, `f0`,
`f1`, `f2`, `f3`, `f01`, `f10`. Each is `<shape> n=<node count>`.

THE WITNESS IS THE SHAPE, AND `gates/axisflip.bend`'s header says why with the measurement: a
graph row (`<OP>x<nsrc>[<src ops>]{order}`, which is what `gates/groupflip.bend` compares) carries
no RESHAPE target shape, no PAD offset and no SHRINK size, so it cannot see a wrong shape at all.
MEASURED: across a fix that moved the port's `flip([1])` result from (4,4,8,8) to (1,4,8,8), the
`<n> Ops.<TOP>/<nsrc> <srcops>` rows were byte-identical. `n=` is here as well and it is the
AXIS-SENSITIVE half: these seven counts are 10 / 28 / 37 / 37 / 37 / 52 / 52, so this lane is
seven distinct measurements rather than one answer repeated.

THE BASE IS (2,4,4,8), NOT (1,4,8,8) AND NOT (4,4,4,4).

  NOT (1,4,8,8), because axis 0 has SIZE 1 there and `movement.py:255`'s
  `if resolve((n:=ret.shape[axis]) <= 1, False): continue` skips it, so `f0` is the base and
  `f01` is `f1` -- two rows that certify nothing.
  NOT (4,4,4,4), because `gates/groupflip.bend` uses it and all four dims are 4, and the defect
  is a substitution that is the identity whenever `shape[0] == shape[axis]`.
  (2,4,4,8) IS THE BEST AVAILABLE AT 256 ELEMENTS: 256 = 2^8 and the partitions of 8 into four
  positive parts are {5,1,1,1} {4,2,1,1} {3,3,1,1} {2,2,2,2}, i.e. (32,2,2,2) (16,4,2,2)
  (8,8,2,2) (4,4,4,4) -- all four repeat a dim, so no rank-4 base of four DISTINCT dims exists at
  256, and rank 3 would have no axis 3.

ONE BASE FOR EVERY ROW, built the way `gates/groupflip-oracle.py`'s `fbase` builds its own: the
256-element buffer, then `mxw_base()`'s (1,4,8,8), then (2,4,4,8), so both lanes reshape the same
number of times and their base graphs agree. `prod((2,4,4,8)) == 256`, so CPython's `_shape` size
check (ops.py:395) passes on both reshapes; the port's `mxw_reshape` does not check, which is why
this is worth stating rather than assuming.
"""

import os
import sys

sys.path.insert(0, os.environ.get("TGROOT", ""))

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop import Ops
from tinygrad.uop.ops import UOp

BASE = Tensor(UOp.new_buffer("PYTHON", 256, dtypes.float)
              ._mop(Ops.RESHAPE, (1, 4, 8, 8))._mop(Ops.RESHAPE, (2, 4, 4, 8)))
CUT = len(set(BASE.uop.toposort())) - 1


def row(nm, axes):
  """`<shape> n=<cut-relative node count>` for `BASE.flip(axes)`, over the ONE shared base.

  `CUT` is computed ON EACH SIDE from that side's own base, for the reason
  `gates/groupflip.bend`'s `gf_cut` gives: upstream moved a BUFFER's size out of `ParamArg` into
  a size CONST src (`72f98ffe0`), so the port's base is 9 nodes and this one is 10 and the
  ABSOLUTE counts differ by one on every row including `base` itself. MEASURED here before the cut
  was added: `base=2,4,4,8 n=10` against `base=2,4,4,8 n=9`.

  `axes=()` IS `flip(())`, upstream's own empty `axis_arg`: `argfix(())` is `()` (helpers.py:22,
  one argument that is a tuple) and `movement.py:254`'s loop body never runs. The shape is
  printed as ints rather than as the `sint` tuple `Tensor.shape` returns, because the port's
  `mx_show` prints ints and a `sint` prints as a symbolic name on one side and a number on the
  other.
  """
  u = BASE.flip(axes).uop
  print(f"{nm}={','.join(str(int(s)) for s in u.shape)} n={len(set(u.toposort())) - CUT}")


row("base", ())
row("fnone", ())
row("f0", (0,))
row("f1", (1,))
row("f2", (2,))
row("f3", (3,))
row("f01", (0, 1))
row("f10", (1, 0))

# `axis1` IS THE GATE'S OWN BLINDNESS GUARD. These are the two lists the defect was about, taken
# from the two expressions themselves: `BASE.shape[1:]` is what the port used and
# `BASE.transpose(0, 1).shape[1:]` is what `movement.py:257-259` uses, because `:256` makes `x`
# the transpose before `crop` and `tail` read its shape. On (2,4,4,8) they are `4,4,8` and
# `2,4,8`; on (4,4,4,4) they would be `4,4,4` and `4,4,4`, and every other row of this gate would
# still be green -- which is why this row is compared rather than a comment.
def dims(s):
  return ",".join(str(int(x)) for x in s)


print(f"axis1={dims(BASE.shape[1:])} vs {dims(BASE.transpose(0, 1).shape[1:])}")