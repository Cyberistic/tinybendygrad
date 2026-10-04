import Base

law a:
  U32 -> IO(U32)

def a(x):
  import "./shim5.c"

law b:
  U32 -> IO(U32)

def b(x):
  import "./shim5.c"

law c:
  U32 -> IO(U32)

def c(x):
  import "./shim5.c"

def main() -> IO(Unit):
  do IO<Unit>:
    x : U32 <- a(1)
    y : U32 <- b(2)
    z : U32 <- c(3)
    IO.print(U32.show((x + y + z : U32)))

#|19