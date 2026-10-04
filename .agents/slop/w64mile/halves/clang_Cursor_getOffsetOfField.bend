# M-2 clang_Cursor_getOffsetOfField -- blocked on I64 by clangshim-gen.py; here over two U32 halves.
import Base

law clang_Cursor_getOffsetOfField:
  Nat -> IO(U32)

def clang_Cursor_getOffsetOfField(C):
  import "./clang_Cursor_getOffsetOfField.c"

law clang_Cursor_getOffsetOfField_lo: IO(U32)

def clang_Cursor_getOffsetOfField_lo():
  import "./clang_Cursor_getOffsetOfField.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- clang_Cursor_getOffsetOfField(0n)
    lo : U32 <- clang_Cursor_getOffsetOfField_lo()
    IO.print("H64 clang_Cursor_getOffsetOfField hi=" ++ Nat.show(U32.to_nat(hi)) ++ " lo=" ++ Nat.show(U32.to_nat(lo)))
