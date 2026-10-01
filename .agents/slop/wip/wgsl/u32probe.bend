import Base

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
      "add=", U32.show(U32.add(1, 2)), " sub=", U32.show(U32.sub(0, 3)),
      " mul=", U32.show(U32.mul(3, 4)), " div=", U32.show(U32.div(7, 2)),
      " xor=", U32.show(U32.xor(12, 10)), " eq=", U32.is_eq(1, 1),
      " lt=", U32.is_lt(1, 2), " ge=", U32.is_ge(1, 2), " zero=", U32.is_zero(0),
      " nat=", U32.show(U32.to_nat(5)), " fnat=", U32.show(Bool.pick(U32, Nat.is_eq(1n, 1n), 1, 0)),
      " sh=", U32.show(U32.shl(1, 4)), " b1=", U32.show(U32.band(12, 10))]))
