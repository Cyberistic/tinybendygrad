import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S

# THE PLANT, BOTH HALVES, ON ONE ROW PER NODE.
#
#   (a) `unshard` and a RANGE-CARRYING `stage` go `?` -> a real dtype AND shape.
#   (b) a node whose SRC is DEFERRED still reads `?`.
#
# (b) IS THE ONE THAT DECIDES WHETHER (a) IS A FIX OR A LIE. It is built by putting a
# RESHAPE whose `marg` is a SPECIAL (the `ssimplify` wall, `marg.of`) UNDER the UNSHARD,
# so `dt_shape`'s src gather refuses it -- `Kahn.go.of`, one-directional, unchanged -- and
# the UNSHARD must refuse with it. Nothing about the width reader changes that, and this
# row is what says so rather than asserting it.
#
# The population is `O.Arena.nodes(ar)` per arena, walked by the compiler, so no node
# index is written by hand anywhere below.

def dt_str(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: O.dt_name(d)
    case None{}: "NONE"

def dim_str.of(s: O.Sint) -> String:
  match s:
    case O.SI{i}: U32.show(H.lo32(i))
    case O.SU{u}: "U"

def dim_str.tail(xs: List<&2, O.Sint>) -> String:
  match xs:
    case Nil{}: ")"
    case x <> tl: String.concat([",", dim_str.of(x), dim_str.tail(tl)])

def dim_str.all(xs: List<&2, O.Sint>) -> String:
  match xs:
    case Nil{}: "()"
    case x <> tl: String.concat(["(", dim_str.of(x), dim_str.tail(tl)])

def sh_str.shape(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{s}: dim_str.all(s)
    case None{}: "NONE"

def sh_str.got(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{s}: sh_str.shape(s)
    case None{}: "NONE"

def sh_str(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  sh_str.got(m)

# THE ROW. `dt` and `sh` come from the MAIN table, which is what the port's renderer
# prints; `?` on this side is exactly the `?` the differ's ledger counts.
def row(+i: U32, +ar: O.Arena, +tb: F.Table) -> String:
  String.concat(["  node#", U32.show(i), " op=", O.Ops.name(O.Arena.op(ar, i)),
    " dtype=", dt_str(F.fold.dt(ar, tb, i)),
    " shape=", sh_str(F.fold.shape(ar, tb, i))])

def rows.go(ns: List<&2, O.Node>, +k: U32, +ar: O.Arena, +tb: F.Table, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case _ <> tl: rows.go(tl, U32.add(k, 1), ar, tb, List.append(&2, String, acc, [row(k, ar, tb)]))

def rows(+ar: O.Arena, +tb: F.Table) -> List<&2, String>:
  rows.go(O.Arena.nodes(ar), 0, ar, tb, Nil{})

def print_all(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case s <> tl: IO.bind(Unit, Unit, IO.print(s), _ => print_all(tl))

def pa() -> O.ParamArg:
  O.ParamArg{0, S.single(), Some{12}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def base_reshape(ar: O.Arena) -> O.Found:
  +c4 = O.UOp.const(ar, O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +sh = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +b  = O.UOp.new(O.Found.ar(sh), O.OpsBUFFER{}, Nil{}, O.AParam{pa()}, O.TNone{})
  O.UOp.new(O.Found.ar(b), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(sh)], O.ANone{}, O.TNone{})

# (a1) `g_unshard` -- `UOp(Ops.UNSHARD, src=(a.uop, UOp.range(2,0,DEVICE)), arg=(0,))`.
# py says `f32` / `(l0:8,l0:3)`: `4 * int(vmax)+1)` with `vmax = 2-1 = 1`.
def g_unshard(ar: O.Arena) -> O.Found:
  +rs = base_reshape(ar)
  +c2 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(2)})
  +r  = O.UOp.range_end(O.Found.ar(c2), O.Found.i(c2), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(rs), O.Found.i(r)], O.ATuple{[0]}, O.TNone{})

# (a2) A RANGE-CARRYING STAGE, WHICH THE CORPUS DOES NOT HAVE. `g_stage` is one src and
# no ranges, so its prepend is empty and the arm was already total. `UOp(Ops.STAGE,
# src=(a, r), arg=None)` is the multi-device `bufferize` shape and is the case this
# change exists for.
def g_stage_rng(ar: O.Arena) -> O.Found:
  +rs = base_reshape(ar)
  +c3 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(3)})
  +r  = O.UOp.range_end(O.Found.ar(c3), O.Found.i(c3), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsSTAGE{}, [O.Found.i(rs), O.Found.i(r)], O.ANone{}, O.TNone{})

# (b) THE THREE REFUSALS, because ONE `?` is not evidence -- it does not say WHICH
# reader refused, and the only thing that matters is that the refusal is the fold's own
# one-directional rule and not a number this change invented.
#
#   b1  a RANGE whose `src[0]` is a SPECIAL, not an integer CONST. `rng_width` REFUSES
#       (it reads only a CONST), where CPython would compute `(x-1).vmax` from x's
#       interval. THIS IS THE REFUSAL THIS CHANGE OWNS.
#   b2  a RESHAPE onto a SYMBOLIC marg. Whether it refuses is `marg`'s business and is
#       measured, not assumed: if the RESHAPE answers `SU`, then the UNSHARD under it
#       refuses at `unshard_scaled` instead, and the row says WHICH.
#   b3  the same as b1 but the RANGE carries a symbolic dim upstream of a CONST end,
#       so the refusal cannot be confused with a missing interval.

# b1: `RANGE(SPECIAL("N"))` -- upstream computes a width, `rng_width` will not.
def g_b1(ar: O.Arena) -> O.Found:
  +rs = base_reshape(ar)
  +c1 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(1)})
  +sp = O.UOp.special(O.Found.ar(c1), O.Found.i(c1), "N")
  +r  = O.UOp.range_end(O.Found.ar(sp), O.Found.i(sp), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(rs), O.Found.i(r)], O.ATuple{[0]}, O.TNone{})

# b2: `RESHAPE(buf, STACK(SPECIAL("N"), CONST(3)))` -- a SYMBOLIC marg under the UNSHARD.
def g_b2(ar: O.Arena) -> O.Found:
  +c1 = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  +sp = O.UOp.special(O.Found.ar(c1), O.Found.i(c1), "N")
  +b  = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, Nil{}, O.AParam{pa()}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  +sh = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(sp), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +rs = O.UOp.new(O.Found.ar(sh), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(sh)], O.ANone{}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(2)})
  +r  = O.UOp.range_end(O.Found.ar(c2), O.Found.i(c2), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(rs), O.Found.i(r)], O.ATuple{[0]}, O.TNone{})

# b3: the RANGE src is fine but `arg` names an axis the shape does not have, so
# `idx_u32` finds nothing and the width is never asked for.
def g_b3(ar: O.Arena) -> O.Found:
  +rs = base_reshape(ar)
  +c2 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(2)})
  +r  = O.UOp.range_end(O.Found.ar(c2), O.Found.i(c2), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(rs), O.Found.i(r)], O.ATuple{[9]}, O.TNone{})

# b4: EXPAND over a SYMBOLIC marg -- the SECOND own-wall, and `expand_ds` reads the same
# `marg` as `reshape_ds`, so this row is what says whether 53 -> 51 rather than 53 -> 49.
def g_b4(ar: O.Arena) -> O.Found:
  +c1 = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  +sp = O.UOp.special(O.Found.ar(c1), O.Found.i(c1), "N")
  +b  = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, Nil{}, O.AParam{pa()}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  +sh = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(sp), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +rs = base_reshape(O.Found.ar(sh))
  +c5 = O.UOp.const(O.Found.ar(rs), O.CInt{H.i64_of_i32(5)})
  +e  = O.UOp.new(O.Found.ar(c5), O.OpsEXPAND{}, [O.Found.i(rs), O.Found.i(sh)], O.ATuple{[5]}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(e), O.CInt{H.i64_of_i32(2)})
  +r  = O.UOp.range_end(O.Found.ar(c2), O.Found.i(c2), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsSTAGE{}, [O.Found.i(e), O.Found.i(r)], O.ANone{}, O.TNone{})

def show(nm: String, +f: O.Found) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(String.concat(["== ", nm, " (root=", U32.show(O.Found.i(f)), ")"])),
    _ => print_all(rows(O.Found.ar(f), F.UOp.fold(O.Found.ar(f)))))

def main() -> IO(Unit):
  IO.bind(Unit, Unit, show("(a1) unshard, RANGE(2) src, arg=(0,)", g_unshard(O.Arena.empty())),
  _ => IO.bind(Unit, Unit, show("(a2) STAGE WITH A RANGE SRC", g_stage_rng(O.Arena.empty())),
  _ => IO.bind(Unit, Unit, show("(b1) RANGE(SPECIAL) -- rng_width refuses", g_b1(O.Arena.empty())),
  _ => IO.bind(Unit, Unit, show("(b2) RESHAPE onto a SYMBOLIC marg", g_b2(O.Arena.empty())),
  _ => IO.bind(Unit, Unit, show("(b3) arg names an axis the shape lacks", g_b3(O.Arena.empty())),
  _ => show("(b4) EXPAND onto a SYMBOLIC marg, under a STAGE", g_b4(O.Arena.empty())))))))