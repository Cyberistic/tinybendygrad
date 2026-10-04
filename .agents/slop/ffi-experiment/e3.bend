import Base

law env:
  IO(String)

def env():
  import "./shim3.c"

law slen2:
  String -> IO(U32)

def slen2(s):
  import "./shim3.c"

def main() -> IO(Unit):
  do IO<Unit>:
    v : String <- env()
    n : U32 <- slen2("tinybendygrad")
    IO.print("ENV " ++ v)
    IO.print("MARSHAL " ++ U32.show(n))