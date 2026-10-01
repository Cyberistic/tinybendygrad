import Base

def dropd.go(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(&2, Char, acc)
    case c <> t:
      match c:
        case '.': dropd.go(t, acc)
        case _: dropd.go(t, List.append(&2, Char, acc, [c]))

def dropd(cs: List<&2, Char>) -> List<&2, Char>:
  dropd.go(cs, Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    a : String = String.from_list(dropd(String.to_list("..ab..c")))
    IO.print(String.concat(["dropd=", a]))
    b : String = String.from_list(List.reverse(&2, Char, dropd(List.reverse(&2, Char, String.to_list("..ab..c")))))
    IO.print(String.concat(["rthenl=", b]))
