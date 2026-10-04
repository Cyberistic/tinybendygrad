# M-2 clang_getEnumConstantDeclUnsignedValue -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_getEnumConstantDeclUnsignedValue:
  Nat -> IO(U32)

def clang_getEnumConstantDeclUnsignedValue(C):
  import "./clang_getEnumConstantDeclUnsignedValue.c"

law clang_getEnumConstantDeclUnsignedValue_lo: IO(U32)

def clang_getEnumConstantDeclUnsignedValue_lo():
  import "./clang_getEnumConstantDeclUnsignedValue.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_getEnumConstantDeclUnsignedValue(0n)
    lo : U32 <- clang_getEnumConstantDeclUnsignedValue_lo()
    IO.print("H64 clang_getEnumConstantDeclUnsignedValue hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
