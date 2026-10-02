import Base

def e32_b(fmt: String) -> Bool:
  match fmt:
    case "VOP1": True{}
    case "VOP2": True{}
    case "VOPC": True{}
    case _: False{}

def or2(a: String, b: String, c: String) -> Bool:
  +x = String.eq(a, b)
  Bool.or(x, String.eq(a, c))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([Bool.to_string(e32_b("VOP2")), "/", Bool.to_string(e32_b("VOP3")), "/", Bool.to_string(or2("x","x","y"))]))
