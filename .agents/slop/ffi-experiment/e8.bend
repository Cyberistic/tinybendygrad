import Base

law mlo:
  IO(U32)

def mlo():
  import "./shim8.c"

law mhi:
  IO(U32)

def mhi():
  import "./shim8.c"

law mnat:
  IO(Nat)

def mnat():
  import "./shim8.c"

def main() -> IO(Unit):
  do IO<Unit>:
    lo : U32 <- mlo()
    hi : U32 <- mhi()
    n : Nat <- mnat()
    IO.print("BEND_GOT lo=" ++ U32.show(lo) ++ " hi=" ++ U32.show(hi))
    IO.print("BEND_NAT " ++ Nat.show(n))