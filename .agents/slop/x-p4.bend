import Base

type Obj is Data:
  OTens{n: U32}
  ODict{kvs: List<&2, Kv>}
  OSeq{es: List<&2, Obj>}
  OOther{}

type Kv is Data:
  Kv{k: String, v: Obj}

def go() -> IO(Unit):
  do IO<Unit>:
    t : Obj = OTens{7}
    d : Obj = ODict{[Kv{"a", t}, Kv{"b", OTens{8}}]}
    s : Obj = OSeq{[d, OTens{9}]}
    match s:
      case OSeq{es}: IO.print(String.concat(["seq_n=", U32.show(U32.from_nat(List.length(&2, Obj, es)))]))
      case _: IO.print("seq_n=?")

def main() -> IO(Unit):
  go()
