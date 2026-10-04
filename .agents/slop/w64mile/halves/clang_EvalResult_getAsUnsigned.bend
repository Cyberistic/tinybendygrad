# M-2 clang_EvalResult_getAsUnsigned -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_EvalResult_getAsUnsigned:
  Nat -> IO(U32)

def clang_EvalResult_getAsUnsigned(E):
  import "./clang_EvalResult_getAsUnsigned.c"

law clang_EvalResult_getAsUnsigned_lo: IO(U32)

def clang_EvalResult_getAsUnsigned_lo():
  import "./clang_EvalResult_getAsUnsigned.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_EvalResult_getAsUnsigned(0n)
    lo : U32 <- clang_EvalResult_getAsUnsigned_lo()
    IO.print("H64 clang_EvalResult_getAsUnsigned hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
