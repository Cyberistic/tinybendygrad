import Base

law mdev_hi:
  IO(U32)

def mdev_hi():
  import "./shim7.c"

law mdev_full:
  IO(Nat)

def mdev_full():
  import "./shim7.c"

law mtag:
  U32 -> IO(U32)

def mtag(x):
  import "./shim7.c"

def main() -> IO(Unit):
  do IO<Unit>:
    hi : U32 <- mdev_hi()
    full : Nat <- mdev_full()
    tg : U32 <- mtag(7)
    IO.print("HIGH32 " ++ U32.show(hi))
    IO.print("FULLNAT_TAG " ++ U32.show(tg))
    IO.print("FULLNAT_EQ " ++ Nat.show(full))