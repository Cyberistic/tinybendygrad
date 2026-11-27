#!/usr/bin/env python3
"""upstream-rangemap-oracle.py -- WHAT UPSTREAM's RANGE MAP AND REALIZE MAP HOLD.

    .venv/bin/python shaders/upstream-rangemap-oracle.py

THE PORT's RANGE MAP IS A TABLE OF POSITIONS AND UPSTREAM's IS A DICT OF NODES, so the two
cannot be compared by printing them. This file answers the QUESTION the port's rows ask
-- "WHICH NODES DOES THE REALIZE MAP HOLD, AND WHAT RANGES DOES EACH NODE CARRY?" -- by
reading upstream's OWN context, at the moment upstream's apply reads it.

WHY IT PATCHES `PatternMatcher.rewrite`. Upstream's `run_rangeify`
(`tinygrad/schedule/indexing.py:182`) builds an `IndexingContext` (`indexing.py:11-17`)
and hands it to two rewrites: `pm_generate_realize_map` (`:188`, which FILLS the realize
map) and `pm_apply_rangeify` (`:311`, which READS it). The context is not an argument of
either -- it is the rewrite's `ctx` -- so the only place a third party can see it is the
rewrite itself. `PatternMatcher.rewrite(self, uop, ctx)` receives it, and the context is
recognisable by its `realize_map` attribute, so the patch prints the map when the range
map is non-empty: that is after the propagation and before the apply.

THE TWO PRINTS. `REALIZE_MAP` is `ctx.realize_map`: the node and the axes it is realized
on -- `None` for a full realize (`indexing.py:36-37`: every `STORE`) and a list for a
partial one (`indexing.py:261`). `RANGE_MAP` is `ctx.range_map`: the node, its INPUT
ranges and its OUTPUT ranges (`indexing.py:306`).

WHY IT MATTERS HERE. Upstream's shader kernel has TWO ranges and the port's had SIX, and
the reason was a MERGE (`indexing.py:238-261`) that mints a new range for every node with
two consumers -- plus a comparison that decides it, which upstream makes on the range
NODES (`r.get_idx()`, `indexing.py:243`) and the port made on the table POSITIONS. This
file is the measurement that says which is which: upstream's value chain is ONE pair of
ranges and the DISTANCE FIELD gets the second pair, because its consumers read it at
different ranges -- so upstream realizes exactly the `STORE` and the DISTANCE FIELD.
"""

import tinygrad.schedule.indexing as IX
from tinygrad import Tensor

N = 16
RADIUS = 0.5
EPS = 0.0001


def shader(x: Tensor, y: Tensor) -> Tensor:
  """THE SHADER, SPELLED AS `shaders/shader-oracle.py` SPELLS IT."""
  dd = (x * x + y * y).sqrt() - RADIUS
  right = dd.pad((0, 1, 0, 0)).shrink(((0, N), (1, N + 1)))
  down = dd.pad((0, 0, 0, 1)).shrink(((1, N + 1), (0, N)))
  dx = dd - right
  dy = dd - down
  fw = dx.maximum(-dx) + dy.maximum(-dy)
  num = dd + fw
  den = (fw + fw) + EPS
  lo = (num / den).maximum(0.0)
  hi = (lo - 1.0).maximum(0.0)
  return 1.0 - (lo - hi)


def rng_str(r) -> str:
  """A RANGE, SHORT: ITS OP, ITS AXIS ID AND ITS EXTENT -- UPSTREAM's `str()` IS THE
  WHOLE SUBGRAPH, AND THE ORACLE's READER WANTS THE RANGE, NOT ITS CONST."""
  if r.op.name == "RANGE":
    return f"RANGE({r.arg[1]},{r.src[0].val})"
  return r.op.name


def main() -> int:
  printed = [False]

  def spy(self, uop, ctx=None):
    if hasattr(ctx, 'realize_map') and len(ctx.range_map) > 0 and not printed[0]:
      printed[0] = True
      print("REALIZE_MAP:")
      for node, axes in ctx.realize_map.items():
        print(f"  {node.op.name} srcs={[s.op.name for s in node.src]} axes={axes}")
      print("RANGE_MAP:")
      for node, (inp, out) in ctx.range_map.items():
        print(f"  {node.op.name} in={[rng_str(r) for r in inp]} out={[rng_str(r) for r in out]}")
    return original(self, uop, ctx)

  original = IX.PatternMatcher.rewrite
  IX.PatternMatcher.rewrite = spy
  shader(Tensor.empty(N, N), Tensor.empty(N, N)).realize()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
