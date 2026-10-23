# T5 -- is `+x : T = v` a legal reusable let?
import Base

def f(a: String, b: String) -> String:
  +c : String = a ++ b
  c ++ c

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(f("x", "y"))
    IO.print("")
