# M-2 clang_getFileTime -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getFileTime:
  Nat -> IO(U32)

def clang_getFileTime(SFile):
  import "./clang_getFileTime.c"

law clang_getFileTime_lo: IO(U32)

def clang_getFileTime_lo():
  import "./clang_getFileTime.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getFileTime(0n)
    lo : U32 <- clang_getFileTime_lo()
    IO.print("H64 clang_getFileTime hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
