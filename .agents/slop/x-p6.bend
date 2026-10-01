import Base

type Kv is Data:
  Kv{k: String, n: U32}

type Obj is Data:
  OTens{k: String, t: U32}
  OMap{es: List<&2, Kv>}
  OSeq{es: List<&2, Obj>}
  OOther{}

def ushow.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: ushow.go(t, String.concat([acc, U32.show(h), " "]))

def ushow(xs: List<&2, U32>) -> String:
  ushow.go(xs, "")

def go() -> IO(Unit):
  do IO<Unit>:
    o : Obj = OMap{[Kv{"a", 1}, Kv{"b", 2}]}
    match o:
      case OMap{es}: IO.print(String.concat(["ok_n=", U32.show(U32.from_nat(List.length(&2, Kv, es)))]))
      case _: IO.print("ok_n=?")
    p : String = "a.b."
    q : List<&1, String> = String.split(p, '.')
    IO.print(String.concat(["nsp=", U32.show(U32.from_nat(List.length(&1, String, q)))]))

def main() -> IO(Unit):
  go()
