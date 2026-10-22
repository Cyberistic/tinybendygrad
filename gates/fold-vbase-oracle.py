#!/usr/bin/env python3
"""fold-vbase-oracle.py -- CPython's answer for the `vb_` ROWS of
`tinybendygrad/uop/fold.bend`: `UOp.base`, `UOp.unsharded_base`,
`UOp.storage_base` and `UOp.is_virtual`.

    .venv/bin/python gates/fold-vbase-oracle.py
    ./bin/bend tinybendygrad/uop/fold.bend | grep '^vb_'
    diff <(the two)

THE CONTRACT. One line per fixture, and the line is the PORT'S OWN SPELLING:

    vb_<tag> op=Ops.X nsrc=K base=Ops.Y bself=B unbase=Ops.Z uself=B
              sbase=Ops.W sself=B virt=B

`base`/`unsharded_base`/`storage_base` are CPython's OWN properties read off a
real `UOp` -- nothing here reimplements a fold, because an oracle that
recomputes the thing it is checking agrees with itself. `bself` is `base is u`,
because an op NAME alone cannot tell "the base is an ADD" from "the base is
THIS ADD", and the three properties are three DIFFERENT answers on one graph.

THE FIXTURES are the ones `fold.bend`'s `vb_*` builders build, node for node,
and the `op=`/`nsrc=` fields are there so a fixture built with the wrong op or
the wrong arity is caught BEFORE the answer is read.

THE THREE PROPERTIES, at the pin (`tinygrad/uop/ops.py`, the vendored tree IS
the declared pin `5c2bf39d6c4b`):

    ops.py:762  def base(self)          if self.op in GroupOp.Movement: return self.src[0].base
                                        if self.op is Ops.DETACH:      return self.src[0].base
                                        return self
    ops.py:769  def unsharded_base(self) ... the same, PLUS Ops.UNSHARD, and the
                                        step is `self.src[0].base` -- the BASE, not
                                        the src's own unsharded base
    ops.py:782  def storage_base(self)  `self` with UNSHARD, BITCAST and AFTER
                                        stripped: a peel over the union set
    ops.py:891  def is_virtual(self)    self.device is None or self.dtype in dtypes.weaks

`dtypes.weaks` is `(weakint, weakfloat)` (tinygrad/dtype.py:160), so a WEAK
dtype on a node that CARRIES A DEVICE is the only way to see the weak half of
`is_virtual` on its own: a weak node is otherwise device-less, so a bare
`CONST(3)` has BOTH halves firing and cannot separate them. `vb_wc` and `vb_wf`
are the two weak dtypes over a device-carrying BUFFER, and they are the rows
that say the WEAK SET is both members and not one.

WHAT IT COMPARES AGAINST, AND THAT IS THE WHOLE CLAIM. `tinygrad` here is the
VENDORED tree at the repo root, and MEASURED 2026-10-22, that tree is
BYTE-IDENTICAL to `upstream/master`'s `tinygrad/` -- 230 of 230 paths, and 230 of
230 blob hashes, the same. So the oracle's answer is UPSTREAM's answer and not a
re-derivation of it: this file needs no CPython install of tinygrad beyond the
repo it lives in, and the thing it measures is the port against upstream master
`5c2bf39d6c4b` rather than against a pin of the port's own making.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reporoot                                                    # noqa: E402

# THE ROOT, BY THE MARKERS `pyproject.toml`, `tinybendygrad/` AND `tinygrad/` -- and a file
# that cannot find one exits 3, REFUSED, NOT A VERDICT, rather than measuring a tree it could
# not identify. `gates/reporoot.py` says why the depth is not a number.
try:
  ROOT = reporoot.root(__file__)
except reporoot.RootNotFound as e:
  print(f"== REFUSED, NOT A VERDICT: {e}", file=sys.stderr)
  raise SystemExit(3)
# THE VENDORED `tinygrad/`, WHICH IS UPSTREAM'S -- see the last paragraph above.
sys.path.insert(0, str(ROOT))
from tinygrad.uop.ops import UOp, Ops, ParamArg                     # noqa: E402
from tinygrad.uop.ops import AxisType                               # noqa: E402
from tinygrad import dtypes                                         # noqa: E402

# A BUFFER(int32) of shape (4,) ON A DEVICE. The device is what makes
# `is_virtual` false, and without it every node is virtual.
def vbuf():
  return UOp(Ops.BUFFER, (UOp.const(4),), ParamArg(0, dtypes.i32, device="CPU"))


def vadd():
  b, c = vbuf(), UOp.const(3)
  return UOp(Ops.ADD, (b, c))


def vmv():
  b, c = vbuf(), UOp.const(2)
  return UOp(Ops.EXPAND, (b, c))


def vus():
  b = vbuf()
  return UOp(Ops.UNSHARD, (b, UOp.range(4, 0, AxisType.DEVICE)), arg=(0,))


def veus():
  u, e = vus(), UOp.const(2)
  return UOp(Ops.EXPAND, (u, e))


def vabc():
  b = vbuf()
  bc = UOp(Ops.BITCAST, (b,), arg=dtypes.i32)
  return UOp(Ops.AFTER, (bc,))


def vcst():
  return UOp.const(3)


def vcast():
  return UOp(Ops.CAST, (UOp.const(3),), arg=dtypes.i32)


def vwc():
  return UOp(Ops.CAST, (vbuf(),), arg=dtypes.weakint)


def vwf():
  return UOp(Ops.CAST, (vbuf(),), arg=dtypes.weakfloat)


FIXTURES = [("add", vadd), ("mv", vmv), ("us", vus), ("eus", veus), ("abc", vabc),
            ("cst", vcst), ("cast", vcast), ("wc", vwc), ("wf", vwf)]


def row(tag, u):
  b, ub, sb = u.base, u.unsharded_base, u.storage_base
  print(f"vb_{tag} op=Ops.{u.op.name} nsrc={len(u.src)} "
        f"base=Ops.{b.op.name} bself={b is u} "
        f"unbase=Ops.{ub.op.name} uself={ub is u} "
        f"sbase=Ops.{sb.op.name} sself={sb is u} "
        f"virt={u.is_virtual}")


for tag, build in FIXTURES:
  row(tag, build())
