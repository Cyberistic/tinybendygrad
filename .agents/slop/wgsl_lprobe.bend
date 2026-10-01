import Base

def cat(us: List<&2, String>) -> String:
  match us:
    case Nil{}: ""
    case h <> t: String.concat([h, "|", cat(t)])

def by_cons(us: List<&2, String>) -> List<&2, String>:
  match us:
    case Nil{}: Nil{}
    case h <> t: h <> by_cons(t)

def by_append(us: List<&2, String>) -> List<&2, String>:
  match us:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, String, by_append(t), [h])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
      "walk_lit=[", cat(["a", "b", "c"]), "]",
      " join_cons=[", String.join(by_cons(["a", "b", "c"]), "-"), "]",
      " join_append=[", String.join(by_append(["a", "b", "c"]), "-"), "]",
      " join_lit=[", String.join(["a", "b", "c"], "-"), "]"]))
