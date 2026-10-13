import Base
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/uop/weak.bend as W
import ./../../../tinybendygrad/tensor.bend as T

def t4() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

def cstr(c: O.Const) -> String:
  match c:
    case O.CFloat{f}: String.concat(["f", F32.show(f)])
    case O.CInt{i}: String.concat(["i", H.i64_text(i)])
    case O.CBool{b}: String.concat(["b", U32.show(Bool.to_u32(b))])
    case _: "?"

def argstr(a: O.Arg) -> String:
  match a:
    case O.APy{v}: cstr(v)
    case _: "-"

def dtnm.go(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

def dtnm(+ar: O.Arena, +h: U32) -> String:
  dtnm.go(W.wk_dt(F.folded(ar), h))

def one(+ar: O.Arena, +h: U32) -> String:
  String.concat([U32.show(h), ": ", O.Ops.name(O.Arena.op(ar, h)), "/", U32.show(O.Arena.nsrc(ar, h)),
    " srcs=", O.Rng.srcops(ar, h), " arg=", argstr(O.Arena.arg(ar, h)), " dt=", dtnm(ar, h)])

def dump.go(+ar: O.Arena, xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      dump.go(ar, t, acc ++ one(ar, h) ++ "\n")

def main() -> IO(Unit):
  +r = T.tn_isfinite(t4())
  +ar = T.Tensor.ar(r)
  do IO<Unit>:
    IO.print(O.Rng.sig(ar, T.Tensor.u(r)))
    IO.print(dump.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, T.Tensor.u(r)), ""))