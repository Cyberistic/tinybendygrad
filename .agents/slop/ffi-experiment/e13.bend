import Base

law nq_proto:
  IO(U32)

def nq_proto():
  import "./shim13.c"

law nq_raw:
  IO(U32)

def nq_raw():
  import "./shim13.c"

law blen:
  IO(U32)

def blen():
  import "./shim13.c"

def main() -> IO(Unit):
  do IO<Unit>:
    a : U32 <- nq_proto()
    b : U32 <- nq_raw()
    n : U32 <- blen()
    IO.print("QUEUE_PROTOCOL " ++ U32.show(a))
    IO.print("QUEUE_OBJC_RUNTIME " ++ U32.show(b))
    IO.print("BUFFER_LENGTH " ++ U32.show(n))