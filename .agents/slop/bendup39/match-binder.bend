type T is Data:
  T{a: U32}

def f(x: U32) -> U32:
  +y = T{x}
  match y:
    case T{a}: a
