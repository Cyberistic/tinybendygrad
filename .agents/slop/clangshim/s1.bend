import Base

# clang_createIndex(excludeDeclarationsFromPCH:int, displayDiagnostics:int) -> CXIndex
# CXIndex = ctypes.c_void_p, so the law is U32 -> U32 -> IO(Nat).
law clang_createIndex:
  U32 -> U32 -> IO(Nat)

def clang_createIndex(a, b):
  import "./s1.c"

def main() -> IO(Unit):
  do IO<Unit>:
    ix : Nat <- clang_createIndex(0, 0)
    IO.print("S1_NAT " ++ Nat.show(ix))