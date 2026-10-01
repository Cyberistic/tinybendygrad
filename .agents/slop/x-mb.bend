import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/uop/symbolic.bend as SY

def raw2(o: O.Op, n: U32, a: F32) -> Maybe<&1, O.Const>:
  SY.exec_alu_f32(o, n, a, 0.0, 0.0)

def raw3(o: O.Op, n: U32, a: F32) -> Maybe<&1, F32>:
  SY.cf(O.CFloat{a})

def main() -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(String.concat(["ok ", U32.show(X.bits_of(X.elem_c(X.elem_of(16, S.int32()))))])), _ => IO.pure(Unit, Unit{}))
