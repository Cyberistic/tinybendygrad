# M-2 clang_Type_getAlignOf -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Type_getAlignOf:
  Nat -> IO(U32)

def clang_Type_getAlignOf(T):
  import "./clang_Type_getAlignOf.c"

law clang_Type_getAlignOf_lo: IO(U32)

def clang_Type_getAlignOf_lo():
  import "./clang_Type_getAlignOf.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Type_getAlignOf(0n)
    lo : U32 <- clang_Type_getAlignOf_lo()
    IO.print("H64 clang_Type_getAlignOf hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
