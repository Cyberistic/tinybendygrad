import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/uop/symbolic.bend as SY

def i16() -> X.Elem: X.elem_of(16, S.int32())

def fbits(x: F32) -> U32: F32.bits(x)

def show(nm: String, v: U32) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(String.concat([nm, " = ", U32.show(v)])), _ => IO.pure(Unit, Unit{}))

def lane(o: O.Op, n: U32, a: F32) -> Maybe<&1, O.Const>:
  SY.exec_alu_f32(o, n, a, 0.0, 0.0)

def lanebits(m: Maybe<&1, O.Const>) -> U32:
  match m:
    case Some{v}: X.bits_of(v)
    case None{}: 999

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- show("mathy(SQRT)", Bool.to_u32(X.op_is_mathy(O.OpsSQRT{})))
    b : Unit <- show("is_f(i16)", Bool.to_u32(X.is_f(i16())))
    c : Unit <- show("b_of(i16)", X.b_of(i16()))
    d : Unit <- show("F32.sqrt(16.0)", fbits(F32.sqrt(16.0)))
    e : Unit <- show("exec_alu_f32(SQRT,1,16.0)", lanebits(lane(O.OpsSQRT{}, 1, 16.0)))
    f : Unit <- show("elem_c(i16)", X.bits_of(X.elem_c(i16())))
    g : Unit <- show("alu1f(SQRT, single, i16)", X.Elem.bits(X.alu1f(O.OpsSQRT{}, S.single(), i16())))
    h : Unit <- show("alu1(SQRT, single, i16)", X.Elem.bits(X.alu1(O.OpsSQRT{}, S.single(), i16())))
    k : Unit <- show("alu1i(SQRT, single, i16)", X.Elem.bits(X.alu1i(O.OpsSQRT{}, S.single(), i16())))
    m : Unit <- show("alu2f(SQRT, single, i16, i16)", X.Elem.bits(X.alu2f(O.OpsSQRT{}, S.single(), i16(), i16())))
    return Unit{}