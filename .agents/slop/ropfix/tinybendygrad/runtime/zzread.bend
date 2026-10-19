import Base

def row(v: U32) -> IO(Unit): IO.print(String.concat(["dec=", U32.show(v)]))
def dd(s: String) -> IO(Unit): row(Maybe.default(&2, U32, U32.read(s), 999))

def go() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- dd("12:")
    b : Unit <- dd("10")
    c : Unit <- dd("-")
    e : Unit <- dd("0")
    IO.print("")

def main() -> IO(Unit): go()
