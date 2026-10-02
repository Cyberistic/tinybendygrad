import Base

def t1(a: String, b: String) -> Bool: String.eq(a, b)
def u1(a: String, b: String) -> Bool: String.eq(a, b) || String.eq(a, b)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
