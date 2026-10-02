import Base

def show_go(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: String.concat([U32.show(h), "|", show_go(t)])

def show(nm: String, xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>: IO.print(String.concat([nm, "=", show_go(xs)]))

def A(xs: List<&2, U32>) -> IO(Unit): show("A_append_xs_9", List.append(&2, U32, xs, [9]))
def B(xs: List<&2, U32>) -> IO(Unit): show("B_append_9_xs", List.append(&2, U32, [9], xs))
def C(xs: List<&2, U32>) -> IO(Unit): show("C_append_xs_7", List.append(&2, U32, xs, [7]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- A([1, 2])
    b : Unit <- B([1, 2])
    c : Unit <- C([1, 2])
    IO.print("end")
