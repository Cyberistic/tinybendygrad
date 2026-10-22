import Base

type D is Data:
  C0{}
  C1{}

def mk() -> D:
  C0{}

def bad() -> Empty:
  match mk():
    case C0{}:
      match mk():
        case C1{}:
          match mk():
