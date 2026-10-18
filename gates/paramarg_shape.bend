# paramarg_shape.bend -- WHERE THE PORT PUTS A BUFFER/PARAM'S SIZE.
#
#   .venv/bin/python gates/paramarg-shape-gate.py
#
# ONE QUESTION, AND IT HAS ONE ANSWER PER LANE: given a size, is the node's shape
# right, and WHERE does the size live?
#
# Upstream moved it. `UOp._buffer` (ops.py:828-830) puts the size in `src[0]` via
# `shape_to_shape_arg((size,))` and no longer passes it to `ParamArg` at all; the
# field was DELETED (upstream 72f98ffe0, "move size from ParamArg to src (#18624)").
# `UOp._shape`'s BUFFER/ALLOC/PARAM arm (ops.py:355-357) then reads `self.src[0]`.
#
# This port did not move it. `ops.bend`'s `ParamArg` still declares `size` in the
# slot `vmin_vmax` occupies upstream, `fold.bend`'s `param_shape.pa` still reads
# `ParamArg.size`, and this driver still BUILDS the size into `ParamArg`.
#
# SO THE TWO LANES ARE ASKED THE SAME QUESTION AND THEY ANSWER IT DIFFERENTLY, and
# the diff IS the finding. There is no `diverges` carve-out here on purpose: a
# carve-out would make this file agree with the port, and this file is written
# against UPSTREAM. `gates/paramarg-shape-gate.py` measures the disagreement.
#
# WHY `nsrc` IS A ROW AND NOT A COMMENT. `shape` alone CANNOT see this defect: the
# port reads the size out of `ParamArg` and upstream reads it out of `src[0]`, and
# both answer `(4)`. The size is right in both. So a gate on shape alone is green
# over a port that encodes it in the wrong place -- which is why
# `gates/fold_graph_census-gate.py` is RED today on 11 of 26 compared rows, every
# one of them a `n=` or `nsrc=` count that moved by one. `nsrc` is the encoding,
# and the encoding is what this file is about.
#
# THE ZERO IS A ROW AND NOT A CORNER CASE. A size of `0` is a SHAPE, `(0,)`, and not
# an absence: `shape_to_shape_arg(())` is `UOp(Ops.STACK)` whose `as_shape` is `()`,
# while `shape_to_shape_arg((0,))` is `UOp(Ops.CONST, arg=0)` whose `as_shape` is
# `(0,)`. A migration that defaults the size, or that treats `0` as `1`, is correct
# on every other row here and wrong on exactly this one, so `pa_shape_0` and
# `pa_same_0_1` are the rows that tell those two apart from doing it right.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def pa(dt: S.Dt, size: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{0, dt, size, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def buf(ar: O.Arena, size: Maybe<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{pa(S.single(), size)}, O.TNone{})

def shapev(+ar: O.Arena, m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "ABSENT"
    case Some{g}: match g:
      case None{}: "none"
      case Some{ds}: F.dims_str(ar, ds)

# ONE ROW: the shape the fold answers, and the src count that ENCODES the size.
def row(nm: String, +f: O.Found) -> IO(Unit):
  +ar = O.Found.ar(f)
  +x = F.folded(ar)
  +tb = F.Folded.t(x)
  +i = O.Found.i(f)
  IO.print(String.concat([nm, "=", shapev(ar, F.UOp.shape(ar, tb, i)), " nsrc=", U32.show(O.Arena.nsrc(ar, i))]))

# IDENTITY: two sizes, one arena, are they the same node? CPython hash-conses a UOp
# by (op, src, arg), so the size is in the key only if it is in `src` or in `arg`.
def same(f: O.Found, g: O.Found) -> String:
  Bool.pick(String, U32.is_eq(O.Found.i(f), O.Found.i(g)), "True", "False")

# IDENTITY, AND THE ARENA MUST BE THREADED OR THE ROW IS AN ARTIFACT. `O.UOp.new`
# APPENDS and answers a `Found` carrying the GROWN arena, so a fixture that calls
# `buf(ar, ...)` twice off the same `ar` has built the FIRST node twice and compared
# it with itself. MEASURED, and the first draft of this file did exactly that and
# printed `pa_same_0_1=True`, which reads as "every size is one node" and is really
# "index 0 is index 0". The threading is `O.Found.ar(previous)`, `f_resh_resh`'s own
# idiom (`gates/fold_graph_census.bend:217`).
#
# The pair that answers it, asked in ONE arena:
#   `reintern` -- build 4, then 6, then 4 AGAIN. If the arena hash-conses, the third
#     node IS the first and `pa_reintern_4_4` is True; if it only appends, it is a
#     third node and the row is False. This measures whether the port interns AT ALL.
#   `distinct` -- the first and the second, which must differ for any size to be
#     visible in the graph at all.
# CPython hash-conses a UOp on (op, src, arg), so both are asked there too and a
# port that interns NOTHING is a finding rather than a pass.
def idrow() -> IO(Unit):
  +a = buf(O.Arena.empty(), Some{4})
  +b = buf(O.Found.ar(a), Some{6})
  +c = buf(O.Found.ar(b), Some{4})
  +d = buf(O.Found.ar(c), Some{0})
  +e = buf(O.Found.ar(d), Some{1})
  +f = buf(O.Found.ar(e), Some{0})
  IO.print(String.concat(["pa_reintern_4_4=", same(a, c), " pa_reintern_0_1=", same(d, f),
                          " pa_distinct_4_6=", same(a, b), " pa_distinct_0_1=", same(d, e)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("pa_shape_none", buf(O.Arena.empty(), None{}))
    b : Unit <- row("pa_shape_0", buf(O.Arena.empty(), Some{0}))
    c : Unit <- row("pa_shape_1", buf(O.Arena.empty(), Some{1}))
    d : Unit <- row("pa_shape_4", buf(O.Arena.empty(), Some{4}))
    e : Unit <- row("pa_shape_6", buf(O.Arena.empty(), Some{6}))
    idrow()