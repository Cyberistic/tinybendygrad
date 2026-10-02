import Base

def t2(a: String, p: String) -> String:
  +hit = String.eq(a, p)
  String.drop(a, 1n)

def u2(a: String, b: String, c: String) -> Bool: Bool.or(String.eq(a, b), String.eq(a, c))
def u3(a: String, b: String, c: String) -> Bool: Bool.or(String.eq(a, b), String.eq(c, b))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
