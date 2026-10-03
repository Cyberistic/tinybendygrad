# A READ-ONLY PROBE. It builds nothing in the tree and imports only; it answers two
# questions graphcmp.py cannot: does the port INTERN two same-length byte blobs as the
# same node (upstream does not -- measured, b.key != b2.key), and what does the port's
# dtype/shape say for a realized BUFFER?
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S

# `ParamArg(slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile,
#  image, buffer, bind_on_realize, val)` (ops.py:26-42).
def bufarg(slot: U32, d: S.Dt, size: U32, bslot: U32) -> O.ParamArg:
  O.ParamArg{slot, d, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}}, False{}, None{},
    Some{bslot}, False{}, None{}}

def ab() -> O.Arg:
  O.ABlob{4}

# Q1 -- interning. Returns the two arena indices and whether they are the SAME node.
def q1() -> String:
  +b1 = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, ab(), O.TNone{})
  +b2 = O.UOp.new(O.Found.ar(b1), O.OpsBINARY{}, Nil{}, ab(), O.TNone{})
  String.concat(["Q1 BINARY#1=", U32.show(O.Found.i(b1)), " BINARY#2=", U32.show(O.Found.i(b2)),
    " SAME-NODE(two different same-length blobs collapse)? ", Bool.show(U32.is_eq(O.Found.i(b1), O.Found.i(b2)))])

# Q1b -- does anything in the port ever WRITE an Opt into applied_opts?
def q1b() -> String:
  String.concat(["Q1b KernelInfo.of().applied_opts length = ",
    U32.show(List.length(&2, U32, O.KernelInfo.applied_opts(O.KernelInfo.of()))),
    "; opts_to_apply is None? ", Bool.show(Maybe.is_none(&1, List, O.KernelInfo.opts_to_apply(O.KernelInfo.of())))])

def bshape(tb: F.Table, ar: O.Arena, k: U32) -> String:
  match F.UOp.shape(ar, tb, k):
    case Some{Some{ds}}: String.concat(["has-", U32.show(List.length(&2, O.Sint, ds)), "-dims"])
    case Some{None{}}: "N"
    case None{}: "R"

def bdt(tb: F.Table, ar: O.Arena, k: U32) -> String:
  match F.UOp.dtype(ar, tb, k):
    case Some{d}: match d:
      case S.Dt{pri, bits, cls, nm}: nm
    case None{}: "R"

# Q2 -- a realized BUFFER, built the way upstream builds one.
def q2() -> String:
  +n = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{bufarg(1, S.single(), 12, 7)}, O.TNone{})
  +tb = F.folded(O.Found.ar(n))
  String.concat(["Q2 BUFFER index=", U32.show(O.Found.i(n)), " dtype=", bdt(F.Folded.t(tb), F.Folded.ar(tb), O.Found.i(n)),
    " shape=", bshape(F.Folded.t(tb), F.Folded.ar(tb), O.Found.i(n))])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(q1())
    b : Unit <- IO.print(q1b())
    c : Unit <- IO.print(q2())
