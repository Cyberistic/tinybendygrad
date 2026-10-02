import Base

type K is Data: K{a: String, b: U32}

def K.a2(x: K) -> String:
  match x:
    case K{a, b}: a

def kv(+e: K, +w: String) -> Maybe<&2, K>:
  Bool.pick(Maybe<&2, K>, String.eq(K.a2(e), w), Some{e}, None{})

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
