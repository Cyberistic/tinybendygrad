# arenasrc_rows.bend -- DOES A SIZE-BEARING NODE POINT AT ITS OWN SIZE?
#
#   .venv/bin/python gates/arenasrc_probe-check.py
#
# NAMED `arenasrc_rows` AND NOT `*probe.bend` BECAUSE `.gitignore:85` IS `*probe.bend`.
# A gate driver that sits behind an ignore rule is the small version of the failure this
# row exists to repair -- an input the tree can clear -- so the driver took the name the
# ignore rules leave alone. `--check-ignore` answers NOT ignored; that is the check.
#
# ONE QUESTION, ANSWERED FOUR TIMES: for a BUFFER/ALLOC/PARAM, does `src[0]` name the
# size node -- in the arena the node itself lives in?
#
# WHY A GREEN BUILD PROVES NOTHING HERE. `Arena.src(ar, i, 0)` answers
# `Maybe.default(..., 0)` (`ops.bend`), so a node whose `src[0]` index names nothing reads
# the arena BOTTOM with no error at all. The self-loop compiles, the gate is silent, and
# `F.Kahn.settled` goes false two layers up. So the acceptance test is these ROWS, not
# `bend --check-only`, and this driver exists to emit them.
#
# THE DEFECT, IN ONE PARAGRAPH. `shape_to_shape_arg.of` returns a `Found` -- the arena AND
# the index -- and `param_src` kept the index and THREW THE ARENA AWAY. Since an `Arena`
# is an immutable `Data` value, `UOp.new(ar, K, param_src(ar, n), ...)` interned the size
# node into a throwaway arena and then interned the node into an arena where that index
# names nothing, so the node came out pointing at ITSELF. MEASURED, the idiom reads
# `next=2 src0_op=BUFFER size=N` (the size CONST was never interned, and `src[0]` is the
# BUFFER) against `next=3 src0_op=CONST size=12` for the threaded spelling.
#
# FOUR BUILDERS, NOT ONE FIXTURE. `idiom_*` is the throwaway-arena shape rebuilt ON
# PURPOSE, and it is the CONTROL: if it ever stops reading BAD then this driver can no
# longer see the defect and every other row is worthless. The other three are the port's
# own: `O.UOp.new.param` (`ops.bend`), `mxw_buf` (`mixin/movement.bend`, the
# BOTTOM-OF-EVERY-GRAPH builder) and `fx_buf` (`function.bend`).
#
# ZERO IS A SHAPE. `Some{0}` is `(0,)` and not an absence, so `mxw_buf0` must read
# `size=0` -- a reader that defaults a missing size to 0 passes every other row here and
# fails exactly this one.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/function.bend as FN
import ./../tinybendygrad/tensor.bend as T

def pa() -> O.ParamArg:
  O.ParamArg{0, S.single(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def mshow(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{n}: U32.show(n)
    case None{}: "N"

# THE CONTROL: the throwaway-arena shape, spelled out so this driver can still SEE the
# defect it is looking for. `param_src` no longer exists as a call site anywhere in the
# port -- `gates/arenasrc_census.py` says 0 -- so the shape is written here directly.
def idiom(+e: O.Arena, size: Maybe<&2, U32>) -> O.Found:
  +t = O.shape_to_shape_arg.of(e, e, size)
  O.UOp.new(e, O.OpsBUFFER{}, [O.Found.i(t)], O.AParam{pa()}, O.TNone{})

# THE PORT'S SPELLING: `UOp.new.param` interns the size into `e` and then interns the node
# into the GROWN `e`.
def threaded(+e: O.Arena, size: Maybe<&2, U32>) -> O.Found:
  O.UOp.new.param(e, O.OpsBUFFER{}, size, O.AParam{pa()}, O.TNone{})

def show(nm: String, +f: O.Found) -> String:
  +ar = O.Found.ar(f)
  +self = O.Found.i(f)
  +s0 = O.Arena.src0(ar, self)
  +pre = nm
  String.concat([pre, "_src0_op=", O.Ops.name.of(O.Arena.op(ar, s0)),
                 " ", pre, "_size=", mshow(O.ParamArg.size(ar, self)),
                 " ", pre, "_nsrc=", U32.show(O.Arena.nsrc(ar, self)),
                 " ", pre, "_next=", U32.show(O.Arena.next(ar))])

def tensor_found(mb: T.Tensor) -> O.Found:
  match mb:
    case T.Tensor{ar, uop, is_param, grad}: O.Found{ar, uop}

# IDENTITY, all six in ONE arena so the indices are comparable: re-interning 4 must give
# the FIRST node back, 4 and 6 must differ, and 0 must be its own node distinct from 1.
def ids() -> String:
  +e = O.Arena.empty()
  +a = threaded(e, Some{4})
  +b = threaded(O.Found.ar(a), Some{6})
  +c = threaded(O.Found.ar(b), Some{4})
  +d = threaded(O.Found.ar(c), Some{0})
  +e1 = threaded(O.Found.ar(d), Some{1})
  +f = threaded(O.Found.ar(e1), Some{0})
  +g = threaded(O.Found.ar(f), None{})
  String.concat(["reintern_4_4=", Bool.show(U32.is_eq(O.Found.i(a), O.Found.i(c))),
                 " distinct_4_6=", Bool.show(Bool.not(U32.is_eq(O.Found.i(a), O.Found.i(b)))),
                 " distinct_0_1=", Bool.show(Bool.not(U32.is_eq(O.Found.i(d), O.Found.i(e1)))),
                 " distinct_0_none=", Bool.show(Bool.not(U32.is_eq(O.Found.i(d), O.Found.i(g))))])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(show("idiom", idiom(O.Arena.empty(), Some{12})))
    b : Unit <- IO.print(show("threaded", threaded(O.Arena.empty(), Some{12})))
    c : Unit <- IO.print(show("mxw_buf", tensor_found(MX.mxw_buf(O.Arena.empty(), 0, 12))))
    d : Unit <- IO.print(show("mxw_buf0", tensor_found(MX.mxw_buf(O.Arena.empty(), 0, 0))))
    e : Unit <- IO.print(show("fx_buf", FN.fx_buf(0, 12, Some{0})))
    f : Unit <- IO.print(ids())
    IO.print(String.concat(["param_src_call_sites_are_a_census_not_a_row"]))