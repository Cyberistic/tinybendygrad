# .agents/slop/browser/addl3.bend -- THE RIGHT NODES. `addl2` picked the FIRST MUL in toposort
# order, and the first MUL in a conv body is `28*cast3` -- inside the INDEX expression, whose srcs are
# a CONST and a RANGE and therefore Aalu, correctly. So that row measures the pass agreeing with
# upstream and says nothing about the value multiply. This one selects by SHAPE:
#   * an INDEX node, and its own src[0]'s addr (upstream ops.py:877-878 inherits it)
#   * the MUL whose src[0] IS an INDEX -- the node `pm_add_loads` is supposed to claim
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/codegen/kernel.bend as KR
import ./../../../tinybendygrad/uop/weak.bend as WK
import ./fchainl.bend as CH
import ./../../../tinybendygrad/runtime/device.bend as DEV

def addr_str(m: Maybe<&2, Maybe<&2, S.Addr>>) -> String:
  match m:
    case None{}: "None"
    case Some{a}:
      match a:
        case None{}: "Some{None}"
        case Some{ad}:
          match ad:
            case S.AGlobal{}: "AGlobal"
            case S.ALocal{} : "ALocal"
            case S.AReg{}   : "AReg"
            case S.Aalu{}   : "Aalu"

def pick_idx.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      pick_idx.go(ar, t, Bool.pick(U32, Bool.and(U32.is_zero(acc),
        O.eq_op(O.Arena.op(ar, n), O.OpsINDEX{})), n, acc))

def pick_mul.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      +hit2 = Bool.and(O.eq_op(O.Arena.op(ar, n), O.OpsMUL{}),
                     O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, n)), O.OpsINDEX{}))
      pick_mul.go(ar, t, Bool.pick(U32, Bool.and(U32.is_zero(acc), hit2), n, acc))

def tbl(+ar: O.Arena) -> F.Table: F.Folded.t(F.folded(ar))

def row(+ar: O.Arena, +n: U32) -> String:
  String.concat(["n=", U32.show(n),
                 " addr=", addr_str(F.fold.addr(ar, tbl(ar), n)),
                 " src0=", U32.show(O.Arena.src0(ar, n)),
                 " src0-addr=", addr_str(F.fold.addr(ar, tbl(ar), O.Arena.src0(ar, n))),
                 " loadable=", Bool.show(KR.kn_alu_loadable(tbl(ar), ar, n)),
                 " at=", U32.show(KR.Ker.at(KR.pm_add_loads(F.folded(ar), n)))])

def nload.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      nload.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, n), O.OpsLOAD{}), U32.add(acc, 1), acc))

def nload(+ar: O.Arena, +root: U32) -> U32:
  nload.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, root), 0)

def body_of(+i: U32) -> String:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar0 = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar0, 0, i, 0)
  +w = WK.wk_commit(ar0, SCH.sc_src0(ar0, kk))
  +r = KR.lower_reduce_all(O.Found.ar(w), O.Found.i(w))
  +ar = O.Found.ar(r)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(r))
  +mul = pick_mul.go(ar, ns, 0)
  +mm = KR.pm_add_loads(F.folded(ar), mul)
  +at = KR.Ker.at(mm)
  +st = DEV.al_pass.go(F.folded(ar), O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(r)),
                       DEV.Lt{ar, Nil{}, False{}})
  +q = DEV.lt_round.fin(O.Found.i(r), st)
  +w2 = DEV.add_loads(ar, O.Found.i(r))
  String.concat(["index(", row(ar, pick_idx.go(ar, ns, 0)), ") mul(", row(ar, mul), ")",
                 " at-is-load=", Bool.show(O.eq_op(O.Arena.op(ar, at), O.OpsLOAD{})),
                 " nmap=", U32.show(U32.from_nat(List.length(&2, DEV.LateRep, DEV.Lt.rs(st)))),
                 " map-of-mul=", U32.show(DEV.lt_get.go(mul, DEV.Lt.rs(st))),
                 " rebuild-root-changed=", Bool.show(Bool.not(U32.is_eq(DEV.LtR.i(q), O.Found.i(r)))),
                 " loads-in-rebuild=", U32.show(nload(DEV.LtR.ar(q), DEV.LtR.i(q))),
                 " loads-before=", U32.show(nload(ar, O.Found.i(r))),
                 " loads-after=", U32.show(nload(O.Found.ar(w2), O.Found.i(w2))),
                 " loads-in-at=", U32.show(nload(KR.Ker.ar(mm), at)),
                 " at-src0-op-index=", Bool.show(O.eq_op(O.Arena.op(KR.Ker.ar(mm), O.Arena.src0(KR.Ker.ar(mm), at)), O.OpsINDEX{})),
                 " at-src0-op-load=", Bool.show(O.eq_op(O.Arena.op(KR.Ker.ar(mm), O.Arena.src0(KR.Ker.ar(mm), at)), O.OpsLOAD{}))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["addl3=", body_of(0)]))
