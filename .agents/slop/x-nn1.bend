import Base
import ./../../tinybendygrad/LAWS/spec.bend as S

def p1(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}: U32.is_eq(pri, 2)

def p2(a: S.Dt, b: S.Dt) -> Bool:
  match a b:
    case S.Dt{pri, bits, cls, nm} S.Dt{pri, bits2, cls2, nm2}: U32.is_eq(bits, bits2)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(Bool.to_u32(p1(S.uint8()))))
    IO.print(U32.show(Bool.to_u32(p2(S.uint8(), S.uint8()))))
