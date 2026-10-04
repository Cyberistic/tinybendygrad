import Base

law slen:
  IO(U32)

def slen():
  import "./shim.c"

def main() -> IO(Unit):
  do IO<Unit>:
    n : U32 <- slen()
    IO.print("SLEN " ++ U32.show(n))

#|SLEN 14