import Base

def show(us: List<&2, U32>) -> List<&2, String>:
  match us:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, String, show(t), [U32.show(h)])

def j(us: List<&2, U32>) -> String: String.join(show(us), ",")

def j2(us: List<&2, U32>) -> String:
  match us:
    case Nil{}: ""
    case h <> t: String.concat([U32.show(h), ",", j2(t)])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["join([10,20,30])=", j([10, 20, 30]),
      "  own_recursion=", j2([10, 20, 30]),
      "  built_by_append=", j(List.append(&2, U32, List.append(&2, U32, Nil{}, [10]), [20]))]))
