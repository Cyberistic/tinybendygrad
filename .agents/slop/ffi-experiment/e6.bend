import Base

law mdev:
  IO(U64)

def mdev():
  import "./shim6.c"

law mname:
  IO(String)

def mname():
  import "./shim6.c"

def live(p: U64) -> String:
  match p == 0u64:
    case True: "NO"
    case other: "YES"

def main() -> IO(Unit):
  do IO<Unit>:
    p : U64 <- mdev()
    n : String <- mname()
    IO.print("METAL " ++ n)
    IO.print("HANDLE_NONZERO " ++ live(p))