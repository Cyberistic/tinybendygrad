import Base

type D is Data:
  C0{}
  C1{}

def bad(e: Empty, d: D, d2: D) -> Empty:
  match d:
    case C0{}:
      match d2:
    case C1{}:
      match d2:
