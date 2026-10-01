import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/tensor.bend as T
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/uop/fold.bend as F

def barg(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def pbuf(+ar: O.Arena, slot: U32, size: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{barg(slot, size, dt)}, O.TNone{})

def ushow(xs: List<&2, U32>) -> String:
  List.show(&2, U32, U32.show, xs)

def go() -> IO(Unit):
  do IO<Unit>:
    f : O.Found = pbuf(O.Arena.empty(), 0, 32, S.single())
    tt : T.Tensor = T.tn_new(O.Found.ar(f), O.Found.i(f))
    fx : F.Folded = F.folded(O.Found.ar(f))
    sh : Maybe<&1, List<&2, O.Sint>> = F.UOp.shape(fx, O.Found.i(f))
    IO.print(String.concat(["param_shape=", String.from_list([])]))
    match sh:
      case Some{ds}: IO.print(String.concat(["param_shape_N=", U32.show(U32.from_nat(List.length(&2, O.Sint, ds)))]))
      case None{}: IO.print("param_shape=None")
    dts : Maybe<&1, S.Dt> = F.UOp.dtype(fx, O.Found.i(f))
    match dts:
      case S.Dt{pri, bits, cls, nm}: IO.print(String.concat(["param_dt=", nm]))
      case None{}: IO.print("param_dt=None")
    IO.print(String.concat(["repr=", T.tn_repr(tt)]))

def main() -> IO(Unit):
  go()
