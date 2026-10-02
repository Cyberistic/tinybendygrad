import Base

def pick(b: Bool) -> List<&2, String>: Bool.pick(List<&2, String>, b, ["t"], ["f"])
def go(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t: Bool.pick(List<&2, String>, String.eq(x, "a"), acc, go(t, List.append(&2, String, acc, [x])))
def mk() -> List<&2, String>: ["a", "a", "b", "b", "c"]
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["pickF=", String.join(pick(False{}), ","), " pickT=", String.join(pick(True{}), ","),
      " go=", String.join(go(mk(), Nil{}), ",")]))
