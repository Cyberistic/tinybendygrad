# T2 -- which parameter shapes the termination checker accepts for a self-call:
# the TAIL of a List<&1,...>, the TAIL of a List<&2,...>, and the tail of a String.
import Base

def walk1(names: List<&1, String>, acc: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: acc
    case n <> t: walk1(t, List.append(&2, String, acc, [n]))

def walk2(names: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: acc
    case n <> t: walk2(t, List.append(&2, String, acc, [n]))

def walk3(s: String, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}: acc
    case SCon{h, t}: walk3(t, List.append(&2, String, acc, [Char.show(h)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : List<&2, String> <- IO.pure(List<&2, String>, walk1(["a", "b"], Nil{}))
    IO.print(String.concat(["walk1=", String.join(a, ",")]))
    b : List<&2, String> <- IO.pure(List<&2, String>, walk2(["a", "b"], Nil{}))
    IO.print(String.concat(["walk2=", String.join(b, ",")]))
    c : List<&2, String> <- IO.pure(List<&2, String>, walk3("ab", Nil{}))
    IO.print(String.concat(["walk3=", String.join(c, ",")]))
    IO.print("")
