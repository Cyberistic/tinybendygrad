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

# Q1 -- interning. Two DIFFERENT upstream blobs of the same length.
def q1() -> String:
  +b1 = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, ab(), O.TNone{})
  +b2 = O.UOp.new(O.Found.ar(b1), O.OpsBINARY{}, Nil{}, ab(), O.TNone{})
  String.concat(["Q1 BINARY#1=", U32.show(O.Found.i(b1)), " BINARY#2=", U32.show(O.Found.i(b2)),
    " arena.next=", U32.show(O.Arena.next(O.Found.ar(b2))),
    " SAME-NODE(two different same-length blobs collapse)? ", Bool.show(U32.is_eq(O.Found.i(b1), O.Found.i(b2)))])

# Q1b -- does the default KernelInfo carry options?
def q1b.len(xs: List<&2, U32>) -> Nat:
  List.length(&2, U32, xs)

def q1b.ota(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{x}: String.concat(["n(", U32.show(U32.from_nat(q1b.len(x))), ")"])
    case _: "N"

def q1b() -> String:
  String.concat(["Q1b KernelInfo.of().applied_opts length = ",
    U32.show(U32.from_nat(q1b.len(O.KernelInfo.applied_opts(O.KernelInfo.of())))),
    " opts_to_apply = ", q1b.ota(O.KernelInfo.opts_to_apply(O.KernelInfo.of()))])

def bshape.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{Some{ds}}: String.concat(["has-", U32.show(U32.from_nat(List.length(&2, O.Sint, ds))), "-dims"])
    case Some{None{}}: "N"
    case None{}: "R"

def bshape(tb: F.Table, ar: O.Arena, k: U32) -> String:
  bshape.of(F.UOp.shape(ar, tb, k))

def bdt.nm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def bdt.of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: bdt.nm(d)
    case None{}: "R"

def bdt(tb: F.Table, ar: O.Arena, k: U32) -> String:
  bdt.of(F.UOp.dtype(ar, tb, k))

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
    IO.pure(Unit, Unit{})

