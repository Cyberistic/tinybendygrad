import Base

# does a self-call accept a CHANGING (growing) argument ahead of the shrinking one?
def take3(as: List<String>, k: Nat, acc: String) -> String:
  match as:
    case Nil{}: acc
    case h <> t: take3(t, Nat.add(k, 1n), String.concat([acc, h, "/"]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(take3(["p", "PKT", "3", "4", "5"], 0, ""))
    return Unit{}