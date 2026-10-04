# M-2 clang_EvalResult_getAsDouble -- blocked on F64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_EvalResult_getAsDouble:
  Nat -> IO(U32)

def clang_EvalResult_getAsDouble(E):
  import "./clang_EvalResult_getAsDouble.c"

law clang_EvalResult_getAsDouble_lo: IO(U32)

def clang_EvalResult_getAsDouble_lo():
  import "./clang_EvalResult_getAsDouble.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_EvalResult_getAsDouble(0n)
    lo : U32 <- clang_EvalResult_getAsDouble_lo()
    IO.print("H64 clang_EvalResult_getAsDouble hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
