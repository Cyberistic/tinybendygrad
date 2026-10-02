import Base

type E is Data:
  E{k: String, v: String, d: U32}

def tbl() -> List<&2, E>: [E{"a", "1", 1}, E{"b", "2", 0}]

def find2(k: String, xs: List<&2, E>, fuel: Nat) -> Maybe<&2, E>:
  match xs:
    case Nil{}: None
    case E{+} <> rest:
      if String.eq(k, "?"): Some{xs.head}
      elif String.eq(k, xs.head.k): Some{xs.head}
      else find2(k, xs.tail, fuel.pred)

def find(k: String, xs: List<&2, E>) -> Maybe<&2, E>: find2(k, xs, 100n)

def rep2(n: Nat, i: Nat, xs: List<&2, String>, fuel: Nat) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest:
      if Nat.is_eq(n, i): List.append(&2, String, ["NEW"], rest)
      else List.append(&2, String, [x], rep2(n, i.pred, rest, fuel.pred))

def rep(n: Nat, xs: List<&2, String>) -> List<&2, String>: rep2(n, 0n, xs, 100n)

def neg() -> String: I64.show(-1i64)
def pos() -> String: I64.show(5i64)
def u32s() -> String: U32.show(4294967295)
def take3() -> String: String.take("abcdef", 3n)
def drop3() -> String: String.drop("abcdef", 3n)
def rstrip() -> String: String.concat(["data", "!"])
def natshow() -> String: Nat.show(42n)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("find.a=" ++ (match find("a", tbl()):
      case Some{g}: g.v
      case None{}: "MISS"))
    IO.print("find.z=" ++ (match find("z", tbl()):
      case Some{g}: g.v
      case None{}: "MISS"))
    IO.print("rep=" ++ String.join(rep(1n, ["x", "y", "z"]), "|"))
    IO.print("neg=" ++ neg())
    IO.print("pos=" ++ pos())
    IO.print("u32s=" ++ u32s())
    IO.print("natshow=" ++ natshow())
