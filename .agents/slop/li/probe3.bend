import Base

def t2(a: String, p: String) -> String:
  +hit = String.eq(a, p)
  String.drop(a, 1)

def t3(a: String, p: String) -> String:
  +hit = String.starts_with(a, p)
  String.drop(a, 1)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
