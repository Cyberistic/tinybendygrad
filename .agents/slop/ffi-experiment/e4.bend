import Base

law cver:
  IO(String)

def cver():
  import "./shim4.c"

def main() -> IO(Unit):
  do IO<Unit>:
    v : String <- cver()
    IO.print("CLANG " ++ v)