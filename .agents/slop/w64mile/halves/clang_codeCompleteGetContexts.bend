# M-2 clang_codeCompleteGetContexts -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_codeCompleteGetContexts:
  Nat -> IO(U32)

def clang_codeCompleteGetContexts(Results):
  import "./clang_codeCompleteGetContexts.c"

law clang_codeCompleteGetContexts_lo: IO(U32)

def clang_codeCompleteGetContexts_lo():
  import "./clang_codeCompleteGetContexts.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_codeCompleteGetContexts(0n)
    lo : U32 <- clang_codeCompleteGetContexts_lo()
    IO.print("H64 clang_codeCompleteGetContexts hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
