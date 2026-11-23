# .agents/slop/browser/addl.bend -- WHY `pm_add_loads` FIRES ON NOTHING IN THE CHAIN.
# The rule's guard is `kn_alu_loadable`: `fold.addr` must answer Some{AGlobal|ALocal|AReg}. So this
# prints what the fold says for the two ways a probe can mint a buffer, side by side.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/codegen/kernel.bend as KR

def show_addr(m: Maybe<&2, Maybe<&2, S.Addr>>) -> String:
  match m:
    case None{}: "None"
    case Some{a}:
      match a:
        case Some{ad}:
          match ad:
            case S.AGlobal{}: "Some{AGlobal}"
            case S.ALocal{} : "Some{ALocal}"
            case S.AReg{}   : "Some{AReg}"
            case S.Aalu{}   : "Some{Aalu}"
        case None{}: "Some{None}"

def rows() -> String:
  # (a) the probe's own constructor: `AParam{ParamArg{... S.AGlobal ...}}`
  +b1 = O.UOp.new_buffer(O.Arena.empty(), S.D1{0}, 196, S.single(), Some{0})
  +a1 = O.Found.ar(b1)
  # (b) `mxw_buf`'s arg: `AParam{mxw_pbuf(slot)}` -- a slot and no addrspace
  +b2 = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{196}, O.AParam{O.ParamArg{0, S.single(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  +a2 = O.Found.ar(b2)
  +t1 = F.Folded.t(F.folded(a1))
  +t2 = F.Folded.t(F.folded(a2))
  String.concat(["new_buffer addr=", show_addr(F.fold.addr(a1, t1, O.Found.i(b1))),
                 " loadable=", Bool.show(KR.kn_alu_loadable(t1, a1, O.Found.i(b1))),
                 " | param-buffer addr=", show_addr(F.fold.addr(a2, t2, O.Found.i(b2))),
                 " loadable=", Bool.show(KR.kn_alu_loadable(t2, a2, O.Found.i(b2)))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["addl=", rows()]))
