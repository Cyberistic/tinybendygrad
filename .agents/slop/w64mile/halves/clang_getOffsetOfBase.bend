# M-2 clang_getOffsetOfBase -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getOffsetOfBase:
  Nat -> Nat -> IO(U32)

def clang_getOffsetOfBase(Parent, Base):
  import "./clang_getOffsetOfBase.c"

law clang_getOffsetOfBase_lo: IO(U32)

def clang_getOffsetOfBase_lo():
  import "./clang_getOffsetOfBase.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getOffsetOfBase(0n, 0n)
    lo : U32 <- clang_getOffsetOfBase_lo()
    IO.print("H64 clang_getOffsetOfBase hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
