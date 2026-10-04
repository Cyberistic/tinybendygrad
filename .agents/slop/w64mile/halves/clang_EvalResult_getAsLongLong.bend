# M-2 clang_EvalResult_getAsLongLong -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_EvalResult_getAsLongLong:
  Nat -> IO(U32)

def clang_EvalResult_getAsLongLong(E):
  import "./clang_EvalResult_getAsLongLong.c"

law clang_EvalResult_getAsLongLong_lo: IO(U32)

def clang_EvalResult_getAsLongLong_lo():
  import "./clang_EvalResult_getAsLongLong.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_EvalResult_getAsLongLong(0n)
    lo : U32 <- clang_EvalResult_getAsLongLong_lo()
    IO.print("H64 clang_EvalResult_getAsLongLong hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
