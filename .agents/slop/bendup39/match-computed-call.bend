type T is Data:
  T{a: U32}

def mk(x: U32) -> T:
  T{x}

def f(x: U32) -> U32:
  match mk(x):
    case T{a}: a
