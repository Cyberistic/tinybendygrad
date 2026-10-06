#!/usr/bin/env python
# fold-mvt-oracle.py -- the CPython oracle for the MOVEMENT-SHAPE rows of
# tinybendygrad/uop/fold.bend (`dt_shape`'s EXPAND / PERMUTE / PAD / SHRINK / FLIP
# arms, ops.py:414-431).
#
# THE CONTRACT. Every row is FOUR FACTS PLUS THE ANSWER IN ONE STRING:
#   mv_<tag> n=<toposort length> op=<root op> nsrc=<src count> srcops=<A|B|C> shape=(..) dtype=<dt>
# and a node Python REFUSES prints `shape=RAISE:<ExcType>`. The four facts are one
# string on purpose (bend2-constraints.md rule 14, line 4050): SWAPPING A PAD'S TWO
# SHAPE ARGS leaves op, nsrc and almost the node count alone.
#
# The fixtures are the ones `fold.bend`'s `g_mv*` builders build, node for node, so a
# diff of the two lanes is the acceptance test:
#
#     .venv/bin/python .agents/slop/oracles/fold-mvt-oracle.py > $OUT/py.txt
#     ./bin/bend tinybendygrad/uop/fold.bend                    > $OUT/bend.txt
#     diff <(grep '^mv_' $OUT/py.txt) <(grep '^mv_' $OUT/bend.txt)
#
# `buf(k)` is BUFFER(int32, size=k) with NO srcs, which is what `g_resh22` builds, so
# the two arenas intern the same nodes. CPython's `toposort()` length is the node count
# the Bend side gets from `List.length(O.UOp.toposort(...))`.
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, shape_to_shape_arg   # noqa: E402
from tinygrad import dtypes                                           # noqa: E402

DIV = {}


def buf(size):
  return UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32, size=size))


def st(*dims):
  return shape_to_shape_arg(tuple(dims))


def shape_of(u):
  # A BARE `RAISE`. Python raises and the fold "does not answer", and those are the
  # same statement in this file's convention -- so the diff cannot tell them apart and
  # the gate instead pins the ANSWERED rows against CPython and pins each refuse with
  # a mutation (see the file's mutation table). The exception TYPE is in the notes
  # below each refusing row.
  try:
    return "(" + ",".join(str(x) for x in u._shape) + ")"
  except Exception:
    return "RAISE"


def sig(u):
  """FOUR FACTS PLUS THE ANSWER, one string, the same spelling as fold.bend."""
  n, op, ns = len(list(u.toposort())), u.op.name, len(u.src)
  sops = "|".join(str(s.op) for s in u.src)
  return f"n={n} op={op} nsrc={ns} srcops={sops} shape={shape_of(u)} dtype={u.dtype.name}"


def row(tag, u):
  print(f"mv_{tag} {sig(u)}")
  return u


def no(tag, u, why):
  """A node the FOLD REFUSES and CPython answers; the row pins the refusal."""
  DIV[tag] = (why, sig(u))
  print(f"mv_{tag} {sig(u)}")


# ---------------------------------------------------------------------------
# THE FIXTURES. `g_mv*` in fold.bend builds each of these node for node.
# ---------------------------------------------------------------------------

# EXPAND. src[1] is a bare CONST (the one-element `as_shape`) or a STACK. There is NO
# check on this arm -- `return tuple(self.marg) + ps` -- so `exp1` is the arm in full.
b4 = buf(4)
row("exp1", UOp(Ops.EXPAND, (b4, UOp.const(2))))
row("exp2", UOp(Ops.EXPAND, (b4, st(2, 3))))

# EXPAND over a NOOP: `GroupOp.Movement`'s dtype is `src[0].dtype` and a NOOP is in
# the `always void` set, so this is the row that says "the dtype arm reads src[0]".
row("expnoop", UOp(Ops.EXPAND, (UOp(Ops.NOOP, (b4,)), UOp.const(2))))

# EXPAND over a SYMBOLIC marg -- the `s.val if s.op is Ops.CONST else ssimplify(s)`
# half of `as_shape`. CPython ANSWERS a shape with a UOp in it; the fold refuses.
sp = UOp(Ops.SPECIAL, (UOp.const(0),), 'N')
no("expsym", UOp(Ops.EXPAND, (b4, UOp(Ops.STACK, (UOp.const(2), sp)))),
   "CPython's shape holds a UOp; `ssimplify` is the wall, so the fold does not answer")

# PAD: `zip(src[1].as_shape, src[2].as_shape)`, and a one-element marg is a bare CONST
# (`shape_to_shape_arg` returns `src[0]` for a 1-tuple, ops.py:110).
row("pad1", UOp(Ops.PAD, (b4, UOp.const(0), UOp.const(6))))
# PAD over a 2-D src: BUFFER(12) -> RESHAPE(4,3), offsets (0,1), sizes (6,5).
b12 = buf(12)
r43 = UOp(Ops.RESHAPE, (b12, st(4, 3)))
row("pad2", UOp(Ops.PAD, (r43, st(0, 1), st(6, 5))))
# `len(ps) != len(self.marg)` -- a two-entry marg over a one-dim src
row("padr", UOp(Ops.PAD, (b4, st(0, 1), st(6, 5))))
# `o + s <= sz` fails: offset 1 over a dim of 4 with a new size of 3
row("padr2", UOp(Ops.PAD, (b4, UOp.const(1), UOp.const(3))))
# A PAD OVER A MOVEMENT OP'S OWN ANSWER -- the fold's EXPAND answer feeds this arm,
# which is the row that makes the EXPAND arm load-bearing rather than decorative.
row("padexp", UOp(Ops.PAD, (UOp(Ops.EXPAND, (b4, UOp.const(2))), st(0, 0), st(6, 6))))

# SHRINK: the other sum, `o + sz <= s`, and the same answer (`the sizes`).
row("shr1", UOp(Ops.SHRINK, (b4, UOp.const(1), UOp.const(2))))
row("shr2", UOp(Ops.SHRINK, (r43, st(0, 1), st(3, 2))))
row("shrr", UOp(Ops.SHRINK, (b4, UOp.const(1), UOp.const(4))))

# PERMUTE: marg is `self.arg` (ops.py:818), the check is `sorted(marg) ==
# list(range(len(ps)))` and the answer is `tuple(ps[i] for i in marg)`.
row("perm", UOp(Ops.PERMUTE, (r43,), (1, 0)))
row("permrep", UOp(Ops.PERMUTE, (r43,), (0, 0)))
row("permlen", UOp(Ops.PERMUTE, (r43,), (1, 0, 2)))

# FLIP: marg is `self.arg` and the answer is `ps`. CPython's arg is a TUPLE OF BOOLS
# (`all(isinstance(x, bool) for x in marg)`), and the arena's `ATuple` is
# `List<&2, U32>` (ops.bend:763), so the bool half of the check is NOT EXPRESSIBLE.
row("flip", UOp(Ops.FLIP, (r43,), (True, False)))
row("fliplen", UOp(Ops.FLIP, (r43,), (True,)))
row("flipint", UOp(Ops.FLIP, (r43,), (1, 0)))

# THE dtype LADDER OVER A NON-int32 SRC, so a fold arm that answered `void` or
# `src[0].dtype` on the wrong node would move this row. `buf(6)`, because
# `prod((6,)) == prod((2,3))` is the RESHAPE's own product check.
b6 = buf(6)
half = UOp(Ops.CAST, (b6,), dtypes.f16)
print(f"mv_cast {sig(half)}")
row("permhalf", UOp(Ops.PERMUTE, (UOp(Ops.RESHAPE, (half, st(2, 3))),), (1, 0)))

# A PAD WITH A SYMBOLIC OFFSET. `resolve(x)` DEFAULTS TO True (ops.py:64), so all
# three of Python's checks pass and it answers the SIZES. The fold refuses: the marg
# walk needs the offset's VALUE and a SPECIAL's value is `ssimplify`'s job.
no("padsym", UOp(Ops.PAD, (b4, sp, st(6))),
   "CPython's `resolve` defaults to True so it answers (6); the fold cannot read a "
   "SPECIAL's value, so it does not answer")

print()
print("== WHAT CPython ANSWERS WHERE THE FOLD REFUSES ==")
for tag, (why, s) in DIV.items():
  print(f"  mv_{tag}: {why}\n      CPython: {s}")

print()
print("== THE `raise`s, BY MESSAGE -- the refuse rows' ground truth ==")
for tag, u, why in [
    ("padr", UOp(Ops.PAD, (b4, st(0, 1), st(6, 5))), "len(ps) != len(marg)"),
    ("padr2", UOp(Ops.PAD, (b4, UOp.const(1), UOp.const(3))), "o + s <= sz"),
    ("shrr", UOp(Ops.SHRINK, (b4, UOp.const(1), UOp.const(4))), "o + sz <= s"),
    ("permrep", UOp(Ops.PERMUTE, (r43,), (0, 0)), "sorted(marg) != range"),
    ("permlen", UOp(Ops.PERMUTE, (r43,), (1, 0, 2)), "sorted(marg) != range"),
    ("fliplen", UOp(Ops.FLIP, (r43,), (True,)), "len(ps) != len(marg)"),
    ("flipint", UOp(Ops.FLIP, (r43,), (1, 0)), "all(isinstance(x, bool)) -- NOT in the arena"),
]:
  try:
    u._shape
    print(f"  mv_{tag}: NO RAISE -- {why}")
  except Exception as e:
    print(f"  mv_{tag}: {type(e).__name__}: {e}")
