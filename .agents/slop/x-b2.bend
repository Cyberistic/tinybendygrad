import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/uop/symbolic.bend as SY

def i(n: U32) -> X.Elem: X.elem_of(n, S.int32())

def f(x: F32) -> U32: F32.bits(x)

def show(+nm: String, +v: U32) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(String.concat([nm, " = ", U32.show(v)])), _ => IO.pure(Unit, Unit{}))

def mathy() -> Bool: X.op_is_mathy(O.OpsSQRT{})

def lanelane() -> Bool: X.is_f(i(16))

def fof() -> F32: X.f_of(i(16))

def fbits() -> U32: X.b_of(i(16))

def raw(o: O.Op, n: U32, a: F32) -> Maybe<&1, O.Const):
  SY.exec_alu_f32(o, n, a, 0.0, 0.0)

def rawv(m: Maybe<&1, O.Const>) -> U32:
  match m:
    case Some{v}: X.bits_of(v)
    case None{}: 999

def via_alu1f() -> U32: X.Elem.bits(X.alu1f(O.OpsSQRT{}, S.single(), i(16)))

def via_alu1() -> U32: X.Elem.bits(X.alu1(O.OpsSQRT{}, S.single(), i(16)))

def via_alu1_i32() -> U32: X.Elem.bits(X.alu1i(O.OpsSQRT{}, S.single(), i(16)))

def elem_c_of16() -> U32: X.bits_of(X.elem_c(i(16)))

def rawn(o: O.Op, n: U32, a: F32) -> Maybe<&1, O.Const>:
  SY.exec_alu_f32(o, n, a, 0.0, 0.0)

def main() -> IO(Unit):
  IO.pure(Unit, Unit{})
