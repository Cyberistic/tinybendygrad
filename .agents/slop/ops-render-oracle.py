#!/usr/bin/env python3
"""CPython oracle for the LEAF arms of `renderer` (tinygrad/uop/render.py:45-58).

    .venv/bin/python .agents/slop/ops-render-oracle.py

Eleven rows, six arms, every one produced by CALLING
`renderer_infer.rewrite(u, {})` -- which is how `ops.py:1618` drives the table. The
six arms are the ones whose answer is a FUNCTION OF THE NODE'S OWN ARG:

  PARAM                 arg.name, else "p" + slot
  BUFFER / ALLOC        arg.name, else "b"/"a" + slot
  CONST                 str(val)
  SPECIAL               arg  -- see the note below

Eleven rows, FIVE arms. The RANGE pair is DELIBERATELY OUT, and the reason is a
measurement rather than a difficulty: `UPat(Ops.RANGE, dtypes.void, name="x")` and
`UPat(Ops.RANGE, name="x")` are two arms and only the second can fire, because a
RANGE's dtype is `weakint` at this pin whatever you construct -- `UOp(Ops.RANGE,
src, arg, AxisType.WEAK, dtypes.void)` still answers `dtypes.weakint`, measured.
A row for an arm that cannot be reached is a row that cannot fail, and the
"loop" spelling would be a claim about a fixture no graph can produce.

The other twenty arms all read `ctx[x.src[k]]`, which is the caller's fold over the
srcs' renderings. That fold is a self-recursive walk and it is the port's next unit;
these five do not touch it, and a def that answers them alone would be a PARTIAL
RENDERER, so the port's entry point is a `Maybe` and the rest are explicit refusals
rather than a fallback that invents a string.

THE SPECIAL ARM IS A NO-MATCH UPSTREAM, and that is a fact about CPython rather
than about the port. `(UPat((Ops.SPECIAL), name="x"), lambda x: x.arg)` returns the
arg itself; for the fixture below the arg is `None`, and `rewrite` treats `None` as
"no rule fired" (`ops.py:1618`: `if (ret:=match(uop, ctx)) is not None`). So the
arm falls through to `(UPat(GroupOp.All, name="x"), lambda x: str(x))` and the row
is a full `UOp(...)` repr. A port that "implemented" the SPECIAL arm faithfully --
returning the arg -- would answer something DIFFERENT from CPython, because CPython
never gets to use it. The row pins that.

`None` is spelled `none` and NOT `none:AttributeError`: this def's `Maybe` is the
refusal of an un-ported arm, and it is a different thing from a raise.

THE VALUES ARE NOT REPR'D. The first draft used `!r` and every row came out quoted,
which is a spelling the port cannot reproduce without a `repr` for `String`; a gate
whose rows carry a decorator neither side has is a gate about the decorator. No row
here contains a newline, so a bare value is unambiguous.
"""
import sys

from tinygrad.uop.render import renderer_infer
from tinygrad.uop.ops import UOp, Ops, ParamArg, AxisType
from tinygrad import dtypes

L = AxisType.LOOP


def row(nm, u):
  print(f"{nm}={renderer_infer.rewrite(u, {})}")


def main():
  # PARAM: named wins, and the slot is only spelled when the name is absent.
  row("rnd_param_named", UOp(Ops.PARAM, (), ParamArg(3, dtypes.int32, name="i"), L))
  row("rnd_param_unnamed", UOp(Ops.PARAM, (), ParamArg(7, dtypes.int32), L))
  # BUFFER and ALLOC share one arm and differ ONLY in the letter, so the two
  # unnamed rows are the pair that makes the letter load-bearing: a def that
  # answered "b" for both would pass every other row in the family.
  row("rnd_buffer_named", UOp(Ops.BUFFER, (), ParamArg(1, dtypes.int32, name="buf"), L))
  row("rnd_buffer_unnamed", UOp(Ops.BUFFER, (), ParamArg(2, dtypes.int32), L))
  row("rnd_alloc_named", UOp(Ops.ALLOC, (), ParamArg(4, dtypes.int32, name="out"), L))
  row("rnd_alloc_unnamed", UOp(Ops.ALLOC, (), ParamArg(5, dtypes.int32), L))
  # CONST: one row per Const arm, because str(val) is spelled by the arm and a
  # single integer row cannot see CBool and CFloat.
  row("rnd_const_int", UOp.const(42))
  row("rnd_const_bool", UOp.const(True))
  row("rnd_const_float", UOp.const(1.5))
  # SPECIAL: see the module docstring -- the arm returns None and never fires.
  row("rnd_special", UOp(Ops.SPECIAL, (), None, L))
  # NOT CLAIMED BY ANY OF THE FIVE, and it is the row that says the port's REFUSAL is
  # real. It has to be an op that reaches `(UPat(GroupOp.All), lambda x: str(x))`,
  # and the first choice -- an ADD -- does NOT: an ADD is in `syms`, so the arm above
  # fires and asks for `ctx[x.src[0]]`, which raises `KeyError` on an empty ctx. That
  # is a THIRD thing this row is not, and finding it is why the row is here: "no leaf
  # arm claims it" is not the same as "it falls through", and an ADD looked like the
  # clean case until it raised. GROUP is unclaimed AND falls through.
  row("rnd_unclaimed", UOp(Ops.GROUP, (UOp.const(1),), ()))
  return 0


if __name__ == "__main__":
  sys.exit(main())
