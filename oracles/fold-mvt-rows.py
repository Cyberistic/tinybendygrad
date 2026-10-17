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
# THE `size=k` ABOVE WAS THE PORT'S RECORD, NOT CPython's, AND IT KILLED THIS FILE.
# Upstream moved the size OUT of ParamArg and INTO `src[0]` in `72f98ffe0` 2026-10-06
# ("move size from ParamArg to src (#18624)"); `UOp._buffer` (ops.py:828-830) is the
# spelling. This file was written 2026-10-07, one day LATER, so `buf(4)` raised
# `TypeError: ParamArg.__init__() got an unexpected keyword argument 'size'` and the
# file printed ZERO ROWS -- a DEAD oracle, not a green one that went red. `buf` is now
# `UOp._buffer(size, dtypes.i32, 0)`, and `ParamArg` is no longer imported: nothing
# else in this file mints one.
# WHY NOT JUST DELETE `size=` -- MEASURED, and it DELETES THE CLAIMS:
# `UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i32))` has no `src`, so ops.py:355-357's
# `return self.src[0].as_shape` raises IndexError on EVERY row here, AND it hash-conses
# `f(4) is f(6) -> True` -- one node for every size. Asserting the node instead raises
# NOTHING: every `mv_` tag below still prints, and only `n=` moves (BUFFER is n=2).
#
# WHAT A `raise` PRINTS: nothing. This file prints `RAISE` for a Python raise and
# `ABSENT` for a node the FOLD does not answer, and the two are the same statement
# in fold.bend's convention -- so the diff cannot distinguish them. The rows where
# they really differ are listed at the bottom under DIVERGES and are NOT smoothed.
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, shape_to_shape_arg               # noqa: E402
from tinygrad import dtypes                                           # noqa: E402


def buf(size):
  return UOp._buffer(size, dtypes.i32, 0)


def st23(ar):
  return shape_to_shape_arg((2, 3))


def dims(ds):
  """A dim as BOTH lanes can spell it. `U(Ops.<OP>:<arg>)` is the agreement: a symbolic
  dim is named by its OWN arg, not by an arena index, so no lane needs the other's
  numbering. MEASURED, over nine PARAM/SPECIALs (`.agents/slop/margsym-probe2.py`),
  `ssimplify` is the identity on every non-point one and the point value on every
  point one, so the op and the arg are enough to name the dim on either side, and
  the `Ops.` prefix is `O.Ops.name`'s own spelling so the two lanes differ nowhere.
  The `:?` cover is for a symbolic dim neither lane can name.
  """
  out = []
  for x in ds:
    if isinstance(x, int):
      out.append(str(x))
    elif x.op is Ops.PARAM:
      out.append(f"U(Ops.PARAM:{x.arg.name})")
    elif x.op is Ops.SPECIAL:
      out.append(f"U(Ops.SPECIAL:{x.arg})")
    else:
      out.append(f"U(Ops.{x.op.name}:?)")
  return "(" + ",".join(out) + ")"


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


def gone(tag):
  """A row whose OP upstream DELETED, so there is no node to answer with.

  Same field spelling, `ABSENT` everywhere, and the tag still prints. Kept in the
  stream on purpose: a tag that stops printing is indistinguishable from a claim
  that was dropped, and dropping one to go green is what these rows must not do.
  """
  print(f"mv_{tag} n=0 op=ABSENT nsrc=0 srcops= shape=ABSENT dtype=ABSENT")


# ---------------------------------------------------------------------------
# g_mv_exp1: BUFFER(4), CONST(2), EXPAND
# ---------------------------------------------------------------------------
b4 = buf(4)
row("exp1", UOp(Ops.EXPAND, (b4, UOp.const(2))))
row("exp23", UOp(Ops.EXPAND, (b4, st23(b4))))
row("expnoop", UOp(Ops.EXPAND, (UOp(Ops.NOOP, (b4,)), UOp.const(2))))

# g_mv_expsym: a SPECIAL `'N'` over an END OF ZERO, whose interval is `[0,-1]` --
# EMPTY. CPython ANSWERS (2, UOp, 4) because EXPAND has no check; the fold refuses,
# because ops.py:408's `all(x >= 0)` is DECIDABLE over an empty interval and
# `sym_dim` will not guess it. This row is the DIVERGE and the printed shape is
# CPython's real answer, not a `RAISE`.
sym = UOp(Ops.SPECIAL, (UOp.const(0),), 'N')
expsym = UOp(Ops.EXPAND, (b4, UOp(Ops.STACK, (UOp.const(2), sym))))
print(f"mv_expsym {sig(expsym)} shape={dims(expsym._shape)} dtype={expsym.dtype.name}")


# ---------------------------------------------------------------------------
# SYMBOLIC DIMS. `ssimplify` on a shape-arg element is `as_shape`'s own
# `s.val if s.op is Ops.CONST else ssimplify(s)` (ops.py:808), and `marg` could not
# answer it at all until `sym_dim` landed. Four fixtures, one per answer `sym_dim`
# has: TWO DIFFERENT PARAMs, a POINT-RANGE PARAM, a SPECIAL over a real end, and a
# BARE PARAM (which is `shape_to_shape_arg`'s one-element spelling, ops.py:108, and
# so exercises `as_shape`'s third arm rather than the STACK walk).
# ---------------------------------------------------------------------------
def var(name, lo=0, hi=0xFFFFFF):
  return UOp.variable(name, lo, hi)


# THE ROW THAT SEPARATES "simplified" FROM "FLATTENED". Two DIFFERENT symbolic dims
# in ONE shape: `n` and `m` are different UOps and CPython's answer keeps them
# apart, so a renderer or a simplifier that collapsed both to one token would print
# `(U(PARAM:?),U(PARAM:?))` or `(U,U)` against CPython's `(U(PARAM:n),U(PARAM:m))`.
# The src is BUFFER(4) so `prod(ps) = 4` against a marg whose product is
# `n*m` -- unresolvable, which is ops.py:410's `resolve(..., False)` DEFAULT and
# therefore NO raise.
row("reshsym_nm", UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (var("n"), var("m"))))))
# THE OTHER DIRECTION: a PARAM whose interval is a POINT is a CONST by
# symbolic.py:269 (`x.const_like(x.vmin) if x.vmin == x.vmax`), so `ssimplify` hands
# back the INT 3 and the shape is `(3, 1)` -- no `U` anywhere. A port that answered
# `SU` here would fail the product check instead (`3*1` against `3`) and leave the
# node unanswered, so this row is what says the point arm ran.
row("reshsym_pt", UOp(Ops.RESHAPE, (buf(3), UOp(Ops.STACK, (var("p", 3, 3), UOp.const(1))))))
# A SPECIAL with a REAL end: the same op as `mv_expsym` and the opposite answer,
# because `[0, 98]` is non-empty and `vmin == vmax` is false.
row("expsym_pos", UOp(Ops.EXPAND, (b4, UOp(Ops.STACK, (UOp.const(2), UOp(Ops.SPECIAL, (UOp.const(99),), 'N'))))))
# `shape_to_shape_arg` of a ONE-element tuple returns `src[0]` itself (ops.py:108),
# so `as_shape` takes its THIRD arm -- `(ssimplify(self),)` -- and `marg`'s CONST and
# `not STACK` arms are the same def. `n` over a BUFFER(4) is `prod 0..0xFFFFFF`
# against `4`: unresolvable, so no raise and the shape is `(U(PARAM:n))`.
row("reshbare", UOp(Ops.RESHAPE, (b4, var("n"))))
# AND THE SAME ARM WITH A POINT: `ssimplify` folds the PARAM to the int 4, the
# products are 4 and 4, and the shape is `(4)`.
row("reshbare_pt", UOp(Ops.RESHAPE, (b4, var("q", 4, 4))))

# THE RESIDUAL, NAMED. `resolve(x, False)` is
# `bool(sx.vmin) if sx.vmin == sx.vmax else False` (ops.py:66), so it is DECIDABLE
# -- and True, i.e. it RAISES -- when the two products' intervals are DISJOINT. A
# fold that cannot multiply intervals cannot see that, so `w` over `[0,3]` against a
# BUFFER(4) is the input class where this port answers and CPython refuses. It is a
# PLANNED DIVERGE with a named cause, not a hole: `mv_expsym` above is the other.
disjoint = UOp(Ops.RESHAPE, (b4, var("w", 0, 3)))
try:
  print(f"mv_reshbare_dis {sig(disjoint)} shape={dims(disjoint._shape)} dtype={disjoint.dtype.name}")
except Exception:
  print(f"mv_reshbare_dis {sig(disjoint)} shape=ABSENT dtype=ABSENT")


# ---------------------------------------------------------------------------
# PAD and SHRINK. `marg` is `tuple(zip(src[1].as_shape, src[2].as_shape))`, and
# `_mop` builds those two args by `zip(*arg)`, so the OFFSETS are src[1] and the
# SIZES are src[2] -- the answer `tuple(sz for _,sz in marg)` is src[2]'s shape.
# A ONE-element arg collapses to a bare CONST (`shape_to_shape_arg`, ops.py:108),
# which is what makes `pad1` a four-node graph. THE ROW ORDER IS `main`'s, so a
# `diff` of the two files is a diff of VALUES: a reordering here would read as a
# value difference and hide the two real ones.
# ---------------------------------------------------------------------------
def pad(b, o, z):
  return UOp(Ops.PAD, (b, UOp.const(o), UOp.const(z)))


def shk(b, o, z):
  return UOp(Ops.SHRINK, (b, UOp.const(o), UOp.const(z)))


# offset 0, size 6 over a source dim of 4: `o+s<=sz` is `0+4<=6`
row("pad1", pad(b4, 0, 6))
# the two-dim accepts. RESHAPE needs a BUFFER of SIX (prod((6,)) == prod((2,3))), and
# the offsets/sizes are two STACKs each -- so the node count is 12 and 10.
b6 = buf(6)
r23 = UOp(Ops.RESHAPE, (b6, st23(b6)))
row("pad23", UOp(Ops.PAD, (r23, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5)))))
# the three `raise`s: a LONGER marg than ps, and one failing sum per arm
row("padr", UOp(Ops.PAD, (b4, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5)))))
row("padr2", pad(b4, 1, 3))
# SHRINK, in the order `main` prints them. `o+sz<=s` is `1+2<=4` for `shr1`.
row("shr1", shk(b4, 1, 2))
row("shr23", UOp(Ops.SHRINK, (r23, shape_to_shape_arg((0, 1)), shape_to_shape_arg((2, 1)))))
row("shrbad", shk(b4, 1, 4))

# PERMUTE. `marg` is `self.arg` (ops.py:818) -- the arena's `ATuple`, a list of plain
# indices -- so it does not read `as_shape` and is NOT behind the `ssimplify` wall the
# port's header recorded for these two ops.
row("perm", UOp(Ops.PERMUTE, (r23,), (1, 0)))
row("permrep", UOp(Ops.PERMUTE, (r23,), (0, 0)))
row("permlen", UOp(Ops.PERMUTE, (r23,), (1, 0, 2)))

# FLIP. `Ops.FLIP` IS NOT A MEMBER UPSTREAM ANY MORE, so there is no node to pin and
# the whole paragraph this file used to carry about `flip_arg` being a tuple of BOOLS
# (movement.py:253) describes code that is GONE. MEASURED: `hasattr(Ops, "FLIP")` is
# False and `grep -rn "Ops.FLIP" tinygrad/` is EMPTY; `tinygrad/mixin/movement.py:233`'s
# `flip` transposes, pads the anti-diagonal and extracts it instead. `fold-probe1.py:40`
# records the same measurement.
# THE TWO ROWS ARE KEPT, NOT DELETED -- see `gone`. Porting them needs the PORT: `O.OpsFLIP`
# is still minted in ops.bend (5 uses) and consumed by prepare/indexing/rangeify/multi and
# mixin-gradient, and fold.bend:2559 still dispatches the arm. That is a retirement.
gone("flip")
gone("fliplen")

print("== DIVERGES (CPython answers, the fold refuses; fold.bend prints ABSENT) ==")
print(f"  mv_expsym: CPython shape {dims(expsym._shape)} -- `s.val if s.op is Ops.CONST "
      f"else ssimplify(s)` over a SPECIAL whose END IS ZERO, whose interval [0,-1] is "
      f"EMPTY; `sym_dim` refuses an empty interval because ops.py:408's `all(x >= 0)` "
      f"is then decidable and this file cannot decide it")
print("  mv_reshbare_dis: CPython shape=ABSENT (it RAISES) while fold.bend answers "
      "`(U(PARAM:w))` -- `resolve`'s default is only reached when the two products' "
      "intervals are NOT disjoint, and this fold cannot multiply intervals")

print()
print("== THE `raise`s, BY MESSAGE -- the refuse rows' ground truth ==")
for tag, u in [("padr", UOp(Ops.PAD, (b4, shape_to_shape_arg((0, 1)), shape_to_shape_arg((6, 5))))),
               ("padr2", pad(b4, 1, 3)), ("shrbad", shk(b4, 1, 4)),
               ("permrep", UOp(Ops.PERMUTE, (r23,), (0, 0))),
               ("permlen", UOp(Ops.PERMUTE, (r23,), (1, 0, 2))),
               ("fliplen", None),
               ("reshbare_dis", disjoint)]:
  if u is None:
    print("  mv_fliplen: NO NODE TO RAISE ON -- Ops.FLIP is not a member upstream")
    continue
  try:
    u._shape
    print(f"  mv_{tag}: NO RAISE")
  except Exception as e:
    print(f"  mv_{tag}: {type(e).__name__}: {e}")

