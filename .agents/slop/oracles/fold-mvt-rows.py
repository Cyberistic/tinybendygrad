#!/usr/bin/env python
# fold-mvt-rows.py -- the CPython oracle for the MOVEMENT rows of
# tinybendygrad/uop/fold.bend, printed in EXACTLY the spelling `main` uses, so the
# acceptance test is a diff of two files and neither side can be nudged:
#
#     .venv/bin/python .agents/slop/oracles/fold-mvt-rows.py > py.txt
#     ./bin/bend tinybendygrad/uop/fold.bend                > bend.txt
#     diff <(grep '^mv_' py.txt) <(grep '^mv_' bend.txt)
#
# `mv_` rows only: the eleven `name=True` rows are fold-internal claims.
#
# THE FIXTURES are `g_mv_*` in fold.bend, node for node. `g_mv_pa(k)` is
# `ParamArg(slot=0, int32, size=k)`, so `buf(4)` is `g_mv_exp1`'s source and the
# node counts agree with the Bend arena because both hash-cons.
#
# WHAT A `raise` PRINTS: nothing. This file prints `RAISE` for a Python raise and
# `ABSENT` for a node the FOLD does not answer, and the two are the same statement
# in fold.bend's convention -- so the diff cannot distinguish them. The rows where
# they really differ are listed at the bottom under DIVERGES and are NOT smoothed.
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, shape_to_shape_arg   # noqa: E402
from tinygrad import dtypes                                           # noqa: E402


def buf(size):
  return UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32, size=size))


def st23(ar):
  return shape_to_shape_arg((2, 3))


def dims(ds):
  # A UOp dim renders as `UOp(<toposort position>)`, which is the SAME integer the
  # Bend side prints (`O.Arena` index) ONLY if both arenas intern in the same order.
  # They do for these fixtures -- both build bottom-up through `UOp.new`/`const` --
  # but the row does not rely on it: `mv_expsym` is a DIVERGE and the port refuses,
  # so the digit never has to match. `id()` is NOT used: it is not reproducible.
  return "(" + ",".join(str(x) if isinstance(x, int) else "UOp" for x in ds) + ")"


def sig(u):
  n, op, ns = len(list(u.toposort())), u.op.name, len(u.src)
  sops = "|".join(str(s.op) for s in u.src)
  return f"n={n} op=Ops.{op} nsrc={ns} srcops={sops}"


def row(tag, u):
  """ONE STRING, four facts plus the answer -- the spelling `sig4`/`mv_row` print.

  A PYTHON RAISE PRINTS `ABSENT`, not `RAISE`, and that is deliberate: `ABSENT` is
  this file's spelling for "no entry in the resolved table", which is what a fold
  refusal IS, and `RAISE` is the spelling for "the entry is there and has no shape".
  For every row where Python raises, the fold does not answer, so the two halves
  agree and the diff is clean. The rows where they genuinely DIFFER -- Python
  answers and the fold cannot -- are printed explicitly below and named in DIVERGES.
  """
  try:
    sh = dims(u._shape)
  except Exception:
    sh = "ABSENT"
  dt = u.dtype.name
  try:
    u._shape
  except Exception:
    dt = "ABSENT"
  print(f"mv_{tag} {sig(u)} shape={sh} dtype={dt}")


# ---------------------------------------------------------------------------
# g_mv_exp1: BUFFER(4), CONST(2), EXPAND
# ---------------------------------------------------------------------------
b4 = buf(4)
row("exp1", UOp(Ops.EXPAND, (b4, UOp.const(2))))
row("exp23", UOp(Ops.EXPAND, (b4, st23(b4))))
row("expnoop", UOp(Ops.EXPAND, (UOp(Ops.NOOP, (b4,)), UOp.const(2))))

# g_mv_expsym: the `ssimplify` wall. CPython ANSWERS (2, UOp, 4); the fold cannot
# read a SPECIAL's value, so it does not answer. This row is the DIVERGE and the
# printed shape is CPython's real answer, not a `RAISE`.
sym = UOp(Ops.SPECIAL, (UOp.const(0),), 'N')
expsym = UOp(Ops.EXPAND, (b4, UOp(Ops.STACK, (UOp.const(2), sym))))
print(f"mv_expsym {sig(expsym)} shape={dims(expsym._shape)} dtype={expsym.dtype.name}")


# ---------------------------------------------------------------------------
# PAD and SHRINK. `marg` is `tuple(zip(src[1].as_shape, src[2].as_shape))`, and
# `_mop` builds those two args by `zip(*arg)`, so the OFFSETS are src[1] and the
# SIZES are src[2] -- the answer `tuple(sz for _,sz in marg)` is src[2]'s shape.
# A ONE-element arg collapses to a bare CONST (`shape_to_shape_arg`, ops.py:110),
# which is what makes `pad1` a four-node graph.
# ---------------------------------------------------------------------------
def pad(b, o, z):
  return UOp(Ops.PAD, (b, UOp.const(o), UOp.const(z)))


def shk(b, o, z):
  return UOp(Ops.SHRINK, (b, UOp.const(o), UOp.const(z)))


# offset 0, size 6 over a source dim of 4: `o+s<=sz` is `0+4<=6`
row("pad1", pad(b4, 0, 6))
# offset 1, size 2: `o+sz<=s` is `1+2<=4`
row("shr1", shk(b4, 1, 2))
# the two-dim accepts. RESHAPE needs a BUFFER of SIX (prod((6,)) == prod((2,3))), and
# the offsets/sizes are two STACKs each -- so the node count is 12 and 10.
b6 = buf(6)
r23 = UOp(Ops.RESHAPE, (b6, st23(b6)))
row("pad23", UOp(Ops.PAD, (r23, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5)))))
row("shr23", UOp(Ops.SHRINK, (r23, shape_to_shape_arg((0, 1)), shape_to_shape_arg((2, 1)))))
# the three `raise`s: a LONGER marg than ps, and one failing sum per arm
row("padr", UOp(Ops.PAD, (b4, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5)))))
row("padr2", pad(b4, 1, 3))
row("shrbad", shk(b4, 1, 4))

# PERMUTE and FLIP. `marg` for both is `self.arg` (ops.py:818) -- the arena's
# `ATuple`, a list of plain indices -- so neither reads `as_shape` and NEITHER is
# behind the `ssimplify` wall the port's header recorded for them.
#
# `flip` builds `flip_arg = tuple([i in axis_arg for i in range(len(self.shape))])`
# (movement.py:253) -- a tuple of BOOLS, one per dim -- and the arena erases True/False
# into 1/0. CPython's `all(isinstance(x, bool))` is measured to be unreachable as a
# rejection: intern the int spelling first and `UOp(Ops.FLIP, src, (True, False))`
# returns the INT node (the ucache key is `(op, src, arg, tag, type(arg))` and
# `type(arg)` is `tuple` for both while `True == 1` as dict keys), so a FLIP built
# through `movement.py` always answers. The LENGTH check is the reachable half.
row("perm", UOp(Ops.PERMUTE, (r23,), (1, 0)))
row("permrep", UOp(Ops.PERMUTE, (r23,), (0, 0)))
row("permlen", UOp(Ops.PERMUTE, (r23,), (1, 0, 2)))
row("flip", UOp(Ops.FLIP, (r23,), (True, False)))
row("fliplen", UOp(Ops.FLIP, (r23,), (True,)))

print("== DIVERGES (CPython answers, the fold refuses; fold.bend prints ABSENT) ==")
print(f"  mv_expsym: CPython shape {dims(expsym._shape)} -- `s.val if s.op is Ops.CONST "
      f"else ssimplify(s)` is the wall, and the fold cannot read a SPECIAL's value")

print()
print("== THE `raise`s, BY MESSAGE -- the refuse rows' ground truth ==")
for tag, u in [("padr", UOp(Ops.PAD, (b4, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5))))),
               ("padr2", pad(b4, 1, 3)), ("shrbad", shk(b4, 1, 4)),
               ("permrep", UOp(Ops.PERMUTE, (r23,), (0, 0))),
               ("permlen", UOp(Ops.PERMUTE, (r23,), (1, 0, 2))),
               ("fliplen", UOp(Ops.FLIP, (r23,), (True,)))]:
  try:
    u._shape
    print(f"  mv_{tag}: NO RAISE")
  except Exception as e:
    print(f"  mv_{tag}: {type(e).__name__}: {e}")
