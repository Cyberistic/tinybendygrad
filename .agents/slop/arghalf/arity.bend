type C3 is Data:
  C3{name: U32, flag: Bool, back: Bool}

def p3(x: C3) -> U32:
  match x:
    case C3{n, f, b}: n

def p4(x: C3) -> U32:
  match x:
    case C3{n, f, b, d}: n

def main() -> IO:
  IO.print("REACHED")
