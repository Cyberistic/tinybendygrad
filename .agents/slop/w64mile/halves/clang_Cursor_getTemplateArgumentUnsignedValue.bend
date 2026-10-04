# M-2 clang_Cursor_getTemplateArgumentUnsignedValue -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Cursor_getTemplateArgumentUnsignedValue:
  Nat -> Nat -> IO(U32)

def clang_Cursor_getTemplateArgumentUnsignedValue(C, I):
  import "./clang_Cursor_getTemplateArgumentUnsignedValue.c"

law clang_Cursor_getTemplateArgumentUnsignedValue_lo: IO(U32)

def clang_Cursor_getTemplateArgumentUnsignedValue_lo():
  import "./clang_Cursor_getTemplateArgumentUnsignedValue.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Cursor_getTemplateArgumentUnsignedValue(0n, 0n)
    lo : U32 <- clang_Cursor_getTemplateArgumentUnsignedValue_lo()
    IO.print("H64 clang_Cursor_getTemplateArgumentUnsignedValue hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
