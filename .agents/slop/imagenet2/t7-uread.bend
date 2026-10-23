# T7 -- U32.read over a char list, and List.append's order.
import Base

def show.go(r: Maybe<&2, U32>) -> String:
  match r:
    case Some{v}: U32.show(v)
    case None{}: "NONE"

def show(cs: List<&2, Char>) -> String:
  show.go(U32.read(String.from_list(cs)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["one=", show(['0'])]))
    IO.print(String.concat(["two=", show(['1'])]))
    IO.print(String.concat(["ten=", show(['1', '0'])]))
    IO.print(String.concat(["appended=", String.from_list(List.append(&2, Char, ['0'], ['1']))]))
    IO.print(String.concat(["text0=", String.from_list(['0'])]))
    IO.print("")
