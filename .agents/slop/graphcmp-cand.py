#!/usr/bin/env python3
"""graphcmp-cand.py -- CANDIDATE GRAPHS, MEASURED. Nothing here is transcribed.

Prints, for each candidate `--graph` value graphcmp.py could grow: the node count, the
per-op census, the set of `arg` ATOM LETTERS that appear, whether any node's `depth` is
non-zero, and the multiset of `shape` texts. The last two are the coverage questions:
a graph whose every `depth` is 0 cannot test R5, and an `arg` letter set that is a
subset of the letters the four existing graphs already reach is not new coverage.

EVERY number below is produced by CALLING CPython on the live tree.
"""
from __future__ import annotations

import collections
import os
import sys

os.environ.setdefault("DEV", "CPU")
import tinygrad.dtype as dtm  # noqa: E402
import tinygrad.uop.ops as opm  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graphcmp as G  # noqa: E402


def g_range():
  """`UOp.range(4, (0, 1))` -- the ONE constructor that writes a non-zero `depth`.
  `UOp.range` builds `arg=(axis_type, axis_id)` (ops.py:643) and `axis_id` is `arg[1:]`,
  so a TUPLE axis_id nests once. Every other node in every existing graph has depth 0,
  which means R5 has never been tested by a graph and a green report is silent on it."""
  return opm.UOp.range(4, (0, 1))


def g_range_flat():
  """`UOp.range(4, 0)` -- the flat reading, depth 0, same op and same dtype. The pair
  (range, range_flat) is the R5 fixture: the two differ in the `depth` field and in
  nothing else that a reader would notice."""
  return opm.UOp.range(4, 0)


def g_cast():
  """`Tensor.empty(4,3).cast(dtypes.half).uop` -- exercises `Ops.CAST`, whose arg is a
  BARE `DType` (ops.py `cast`: `UOp(Ops.CAST, (self,), dtype)`), so the `ADt` arm of the
  arg taxonomy gets a node for the first time."""
  from tinygrad import Tensor
  return Tensor.empty(4, 3).cast(dtm.dtypes.half).uop


def g_define():
  """A PARAM node via `UOp.def_param` -- the reader the rest of the tree uses. MEASURED,
  not assumed: this fixture first spelled itself `Tensor.empty(4,3).uop.define()` and
  that raised `AttributeError: 'UOp' object has no attribute 'define'`, so the naive
  spelling was not available and the signature had to be read off the live tree."""
  return opm.UOp.param(0, dtm.dtypes.float, 12, "CPU")


def g_special():
  """`UOp.special(4, "inf")` -- `Ops.SPECIAL`, a str arg on a node that is not a RANGE
  and not a shape, so the `AStr` arm is separated from `KernelInfo.name`'s use of it."""
  return opm.UOp.special(4, "inf")


def g_binary():
  """`UOp(Ops.BINARY, (), b"tiny")` -- the `y` blob atom, currently a LENGTH-ONLY field
  on both sides. Two same-length different-content blobs are the pair that shows it."""
  return opm.UOp(opm.Ops.BINARY, (), b"tiny")


CANDS = {"range": g_range, "rangeflat": g_range_flat, "cast": g_cast, "define": g_define,
         "special": g_special, "binary": g_binary}


def letters_in(arg: str) -> set:
  """The set of ATOM LETTERS at value positions in `arg`. A letter is an atom only
  where a value starts (offset 0 or after `( , : =`), which is graphcmp.py's own
  `at_value` rule -- a `D` inside the string payload `sDefault` is not an atom."""
  out = set()
  for i, c in enumerate(arg):
    if (i == 0 or arg[i - 1] in "(,:=") and c not in "n(":
      out.add(c)
  return out


def census(name: str, ast) -> None:
  nodes = list(ast.toposort())
  ops = collections.Counter(n.op.name for n in nodes)
  letters, shapes, depths = set(), set(), set()
  for n in nodes:
    letters |= letters_in(G.carg(n.op, n.arg))
    shapes.add(G.cshape(n))
    depths.add(G.cdepth(n))
  print(f"== {name}: {len(nodes)} nodes, ops={dict(sorted(ops.items()))}")
  print(f"   depth values={sorted(depths)}  shape values={sorted(shapes)}")
  print(f"   letters={''.join(sorted(letters))}")
  print(f"   args={[G.carg(n.op, n.arg) for n in nodes]}")


def main() -> int:
  G.load_tinygrad()
  import tinygrad
  print(f"# tree={tinygrad.__file__} DEV={os.environ['DEV']}")
  for name in sorted(CANDS):
    census(name, CANDS[name]())
  return 0


if __name__ == "__main__":
  sys.exit(main())