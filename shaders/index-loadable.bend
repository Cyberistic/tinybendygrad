# shaders/index-loadable.bend -- IS `INDEX` LOADABLE? ONE PREDICATE, ASKED IN ISOLATION.
#
# `pm_add_loads` now runs (`.agents/slop/pipelinecensus/execfull.bend`'s `c_len` 17 -> 721) and
# still adds NO `LOAD`, so `kn_load_one`'s test returned False for every INDEX operand and the
# C keeps `(data1_12+idx)` where it needs `*(data1_12+idx)`.
#
# `kn_alu_loadable` is `F.fold.addr` and a membership test on GLOBAL/LOCAL/REG, so the question
# is what the fold answers for an `INDEX` over a `BUFFER`. THE ANSWER HERE IS IN ISOLATION --
# no scheduler, no lowering -- and that is the point: it separates "the fold cannot answer"
# from "the fold does not SETTLE this node at that point in the pipeline".
#
# IT IS A PROBE AND NOT A GATE.

import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/uop/fold.bend as F
import ../tinybendygrad/helpers.bend as H
import ../tinybendygrad/uop/render.bend as R
import ../tinybendygrad/LAWS/spec.bend as S
import ../tinybendygrad/codegen/kernel.bend as K
import ../tinybendygrad/mixin/movement.bend as MX

def yn(b: Bool) -> String:
  Bool.pick(String, b, "True", "False")

def addr_s(m: Maybe<&2, Maybe<&2, S.Addr>>) -> String:
  match m:
    case None{}: "None"
    case Some{None{}}: "Some(None)"
    case Some{Some{a}}: R.addr_name(a)

def rows() -> List<&2, String>:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{256}, O.AParam{MX.mxw_pbuf(0)}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(7)})
  +ix = O.UOp.new(O.Found.ar(c), O.OpsINDEX{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(ix), O.CInt{H.i64_of_i32(8)})
  +ix2 = O.UOp.new(O.Found.ar(c2), O.OpsINDEX{}, [O.Found.i(b), O.Found.i(c2)], O.ANone{}, O.TNone{})
  +ml = O.UOp.new(O.Found.ar(ix2), O.OpsMUL{}, [O.Found.i(ix), O.Found.i(ix2)], O.ANone{}, O.TNone{})
  +ar = O.Found.ar(ml)
  +tb = F.Folded.t(F.folded(ar))
  +mu = K.pm_add_loads(F.folded(ar), ar, Nil{}, Nil{}, O.Found.i(ml))
  +ma = K.Ker.ar(mu)
  +mi = K.Ker.at(mu)
  +mm = K.kn_map_load([O.Found.i(ix)], Nil{}, Nil{}, ar)
  +tr = K.al_try.go(True{}, 0, Nil{}, Nil{}, ar, O.Found.i(ml))
  +a0 = K.al_0.of(True{}, ar, O.Found.i(ml), K.kn_map_load.go([O.Found.i(ix), O.Found.i(ix2)], Nil{}, Nil{}, K.ALS{ar, Nil{}}))
  [String.concat(["buffer_addr=", addr_s(F.fold.addr(ar, tb, O.Found.i(b)))]),
   String.concat(["index_addr=", addr_s(F.fold.addr(ar, tb, O.Found.i(ix)))]),
   String.concat(["index_loadable=", yn(K.kn_alu_loadable(tb, ar, O.Found.i(ix)))]),
   String.concat(["mapped_op=", O.Ops.name(O.Arena.op(K.ALS.ar(mm), Maybe.default(&2, U32, List.get(&2, U32, K.ALS.ss(mm), 0n), 0)))]),
   String.concat(["mul_fired=", yn(Bool.not(U32.is_eq(mi, O.Found.i(ml))))]),
   String.concat(["mul_at_op=", O.Ops.name(O.Arena.op(ma, mi))]),
   String.concat(["at0=", U32.show(mi)]),
   String.concat(["arena_next=", U32.show(O.Arena.next(ma))]),
   String.concat(["tried_op=", O.Ops.name(O.Arena.op(K.Ker.ar(tr), K.Ker.at(tr)))]),
   String.concat(["al0_op=", O.Ops.name(O.Arena.op(K.Ker.ar(a0), K.Ker.at(a0)))]),
   String.concat(["al0_nsrc=", U32.show(U32.from_nat(List.length(&2, U32, O.Arena.srcs(K.Ker.ar(a0), K.Ker.at(a0)))))]),
   String.concat(["mul_at_src0_op=", O.Ops.name(O.Arena.op(ma, O.Arena.src(ma, mi, 0)))])]

def put(rs: List<&2, String>) -> IO(Unit):
  match rs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +r <> rest:
      do IO<Unit>:
        a : Unit <- IO.print(r)
        b : Unit <- put(rest)
        IO.pure(Unit, b)

def main() -> IO(Unit): put(rows())
