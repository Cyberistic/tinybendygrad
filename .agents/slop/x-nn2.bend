import Base

type P is Data:
  P{k: String, n: U32}

def pk(f: P) -> String:
  match f:
    case P{k, n}: k

def pn(f: P) -> U32:
  match f:
    case P{k, n}: n

def pkeys.go(+xs: List<&2, P>, +i: Nat, +acc: String) -> String:
  match i xs:
    case _ Nil{}: acc
    case n +x <> t: pkeys.go(t, Succ{n}, String.append(acc, String.append(pk(x), String.append(",", Nat.show(n)))))

def pchar(s: String) -> Bool: String.starts_with(s, ".")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(pkeys.go([P{"a", 1}, P{"b", 2}, P{"c", 3}], 0n, ""))
    IO.print(Nat.show(Succ{Succ{0n}}))
    IO.print(U32.show(Bool.to_u32(pchar("."))))
    IO.print(U32.show(Bool.to_u32(pchar("x"))))
