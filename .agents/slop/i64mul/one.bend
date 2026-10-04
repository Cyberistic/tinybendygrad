import Base
import ./../../../tinybendygrad/helpers.bend as H

def pphi(r: H.PP) -> U32:
  match r:
    case H.PP{p00, p01, p10, p11, cross, carry, t, hi}: hi

def main() -> IO(Unit):
  +m = H.i64_of_hi_lo(2147483648, 0)
  +one = H.i64_of_hi_lo(0, 1)
  do IO<Unit>:
    IO.print(String.concat(["u64_mul(min,min)=", H.i64_text(H.u64_mul(m, m))]))
    IO.print(String.concat(["u64_mul(min,1)=", H.i64_text(H.u64_mul(m, one))]))
    IO.print(String.concat(["pp_hi(2^63,2^63)=", U32.show(pphi(H.pp_core(2147483648, 0)))]))
    IO.print(String.concat(["pp_hi(1,1)=", U32.show(pphi(H.pp_core(1, 1)))]))
