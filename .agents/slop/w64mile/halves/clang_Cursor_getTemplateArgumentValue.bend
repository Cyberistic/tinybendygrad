# M-2 clang_Cursor_getTemplateArgumentValue -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Cursor_getTemplateArgumentValue:
  Nat -> Nat -> IO(U32)

def clang_Cursor_getTemplateArgumentValue(C, I):
  import "./clang_Cursor_getTemplateArgumentValue.c"

law clang_Cursor_getTemplateArgumentValue_lo: IO(U32)

def clang_Cursor_getTemplateArgumentValue_lo():
  import "./clang_Cursor_getTemplateArgumentValue.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Cursor_getTemplateArgumentValue(0n, 0n)
    lo : U32 <- clang_Cursor_getTemplateArgumentValue_lo()
    IO.print("H64 clang_Cursor_getTemplateArgumentValue hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
