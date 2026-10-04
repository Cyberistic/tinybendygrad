# M-2 clang_Type_getOffsetOf -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Type_getOffsetOf:
  Nat -> String -> IO(U32)

def clang_Type_getOffsetOf(T, S):
  import "./clang_Type_getOffsetOf.c"

law clang_Type_getOffsetOf_lo: IO(U32)

def clang_Type_getOffsetOf_lo():
  import "./clang_Type_getOffsetOf.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Type_getOffsetOf(0n, "")
    lo : U32 <- clang_Type_getOffsetOf_lo()
    IO.print("H64 clang_Type_getOffsetOf hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
