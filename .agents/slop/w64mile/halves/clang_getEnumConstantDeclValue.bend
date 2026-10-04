# M-2 clang_getEnumConstantDeclValue -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getEnumConstantDeclValue:
  Nat -> IO(U32)

def clang_getEnumConstantDeclValue(C):
  import "./clang_getEnumConstantDeclValue.c"

law clang_getEnumConstantDeclValue_lo: IO(U32)

def clang_getEnumConstantDeclValue_lo():
  import "./clang_getEnumConstantDeclValue.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getEnumConstantDeclValue(0n)
    lo : U32 <- clang_getEnumConstantDeclValue_lo()
    IO.print("H64 clang_getEnumConstantDeclValue hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
