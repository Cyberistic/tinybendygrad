import Base

# THE FOREIGN-DEF SHAPE, measured the hard way. A `.c` effect source is bound
# by an UNTYPED `def`; the types live on a separate `law` of the same name.
# A typed `def ... -> IO(U32)` with a `.c` import is rejected with "a foreign
# def without a .js import", and a `.js` effect source must call
# io_eff(CID(name), name_run, need) itself. And a foreign def cannot be RUN by
# `bend <file>` at all: it needs `bend <file> -o out.c` and then `cc`.
law f64_add:
  U32 -> U32 -> U32 -> U32 -> IO(U32)

def f64_add(a, b, c, d):
  import "./f4_add.c"

law f64_add_lo:
  IO(U32)

def f64_add_lo():
  import "./f4_add.c"

def main() -> IO(Unit):
  do IO<Unit>:
    h0 : U32 <- f64_add(U32.from_nat(1073217536n), U32.from_nat(0n), U32.from_nat(1073872896n), U32.from_nat(0n))
    l0 : U32 <- f64_add_lo()
    h1 : U32 <- f64_add(U32.from_nat(1072693248n), U32.from_nat(0n), U32.from_nat(1071644672n), U32.from_nat(0n))
    l1 : U32 <- f64_add_lo()
    h2 : U32 <- f64_add(U32.from_nat(0n), U32.from_nat(0n), U32.from_nat(0n), U32.from_nat(0n))
    l2 : U32 <- f64_add_lo()
    IO.print("W-4 row0 hi=" ++ Nat.show(U32.to_nat(h0)) ++ " lo=" ++ Nat.show(U32.to_nat(l0)))
    IO.print("W-4 row1 hi=" ++ Nat.show(U32.to_nat(h1)) ++ " lo=" ++ Nat.show(U32.to_nat(l1)))
    IO.print("W-4 row2 hi=" ++ Nat.show(U32.to_nat(h2)) ++ " lo=" ++ Nat.show(U32.to_nat(l2)))
