# M-2 clang_getArraySize -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getArraySize:
  Nat -> IO(U32)

def clang_getArraySize(T):
  import "./clang_getArraySize.c"

law clang_getArraySize_lo: IO(U32)

def clang_getArraySize_lo():
  import "./clang_getArraySize.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getArraySize(0n)
    lo : U32 <- clang_getArraySize_lo()
    IO.print("H64 clang_getArraySize hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
