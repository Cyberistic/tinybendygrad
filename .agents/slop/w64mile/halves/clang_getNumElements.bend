# M-2 clang_getNumElements -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getNumElements:
  Nat -> IO(U32)

def clang_getNumElements(T):
  import "./clang_getNumElements.c"

law clang_getNumElements_lo: IO(U32)

def clang_getNumElements_lo():
  import "./clang_getNumElements.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getNumElements(0n)
    lo : U32 <- clang_getNumElements_lo()
    IO.print("H64 clang_getNumElements hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
