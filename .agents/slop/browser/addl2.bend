# .agents/slop/browser/addl2.bend -- WHY `pm_add_loads` CLAIMS NOTHING ON A REAL KERNEL BODY.
# MEASURED: `at=0` for both an INDEX and the MUL that consumes it, so no LOAD is ever minted and the
# rendered C multiplies POINTERS (`cc` refuses it). The guard the rule asks is `kn_alu_loadable`, i.e.
# `fold.addr` in {GLOBAL, LOCAL, REG}, and the last row here is that fold for the MUL's own srcs.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/codegen/kernel.bend as KR
import ./../../../tinybendygrad/uop/weak.bend as WK
import ./fchainl.bend as CH

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

def addr_row.go(+ar: O.Arena, +tb: F.Table, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t:
      addr_row.go(ar, tb, t, List.append(&2, String, acc, [addr_str(F.fold.addr(ar, tb, x))]))

def load_row.go(+ar: O.Arena, +tb: F.Table, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case x <> t:
      load_row.go(ar, tb, t, List.append(&2, String, acc, [Bool.show(KR.kn_alu_loadable(tb, ar, x))]))

def pick.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      pick.go(ar, t, Bool.pick(U32, Bool.and(U32.is_zero(acc),
        O.eq_op(O.Arena.op(ar, n), O.OpsMUL{})), n, acc))

def body_of(+i: U32) -> String:
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  +w = WK.wk_commit(ar, SCH.sc_src0(ar, kk))
  +r = KR.lower_reduce_all(O.Found.ar(w), O.Found.i(w))
  +a = O.Found.ar(r)
  +mul = pick.go(a, O.UOp.toposort(O.Arena.budget(a), a, O.Found.i(r)), 0)
  +ss = KR.kn_srcs(a, mul)
  +at = KR.Ker.at(KR.pm_add_loads(F.folded(a), mul))
  String.concat(["mul=", U32.show(mul), " at=", U32.show(at),
                 " srcs=", U32.show(U32.from_nat(List.length(&2, U32, ss))),
                 " loadable=", String.join(load_row.go(a, F.Folded.t(F.folded(a)), ss, Nil{}), ","),
                 " addr=", String.join(addr_row.go(a, F.Folded.t(F.folded(a)), ss, Nil{}), ",")])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["addl2=", body_of(0)]))
