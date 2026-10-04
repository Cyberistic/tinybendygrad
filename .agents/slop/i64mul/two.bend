import Base
import ./../../../tinybendygrad/helpers.bend as H

def pphi(r: H.PP) -> U32:
  match r:
    case H.PP{p00, p01, p10, p11, cross, carry, t, hi}: hi

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["pp_hi(2^63,1)=", U32.show(pphi(H.pp_core(2147483648, 1)))]))
    IO.print(String.concat(["pp_hi(1,2^63)=", U32.show(pphi(H.pp_core(1, 2147483648)))]))
    IO.print(String.concat(["pp_hi(0,2^63)=", U32.show(pphi(H.pp_core(0, 2147483648)))]))
    IO.print(String.concat(["pp_hi(2^63,0)=", U32.show(pphi(H.pp_core(2147483648, 0)))]))
    IO.print(String.concat(["pp_hi(2^31,2^31)=", U32.show(pphi(H.pp_core(2147483648, 2147483648)))]))
