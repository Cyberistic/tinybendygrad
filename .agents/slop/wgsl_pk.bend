import Base
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/LAWS/spec.bend as S

def b(x: Bool) -> String: Bool.pick(String, x, "T", "F")

def addrreg(a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
      " lt4=", b(U32.is_lt(S.Dt.itemsize(S.uint8()), 4)),
      " nehalf=", b(Bool.not(O.eq_dt(S.uint8(), S.half()))),
      " eqdt_u8_h=", b(O.eq_dt(S.uint8(), S.half())),
      " eqdt_u8_u8=", b(O.eq_dt(S.uint8(), S.uint8())),
      " and12=", b(Bool.and(True{}, True{})),
      " addrreg=", b(addrreg(S.AGlobal{}))]))
