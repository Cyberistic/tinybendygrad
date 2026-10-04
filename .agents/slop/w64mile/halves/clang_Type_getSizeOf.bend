# M-2 clang_Type_getSizeOf -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Type_getSizeOf:
  Nat -> IO(U32)

def clang_Type_getSizeOf(T):
  import "./clang_Type_getSizeOf.c"

law clang_Type_getSizeOf_lo: IO(U32)

def clang_Type_getSizeOf_lo():
  import "./clang_Type_getSizeOf.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Type_getSizeOf(0n)
    lo : U32 <- clang_Type_getSizeOf_lo()
    IO.print("H64 clang_Type_getSizeOf hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
