import Base

type K is Data: K{a: String}

def go(t: List<&2, K>, w: String, acc: Maybe<&2, K>) -> Maybe<&2, K>:
  match acc:
    case Some{g}: Some{g}
    case None{}:
      match t:
        case Nil{}: None{}
        case k <> r: go(r, w, kv(k, w))

def kv(+k: K, +w: String) -> Maybe<&2, K>:
  Bool.pick(Maybe<&2, K>, String.eq(k.a, w), Some{k}, None{})

def K.a(x: K) -> String:
  match x:
    case K{a}: a

def find(xs: List<&2, K>, w: String) -> Maybe<&2, K>: go(xs, w, None{})

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
