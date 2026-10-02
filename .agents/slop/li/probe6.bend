import Base

def b1(+s: String, +p: String) -> String:
  Bool.pick(String, String.starts_with(s, p), String.drop(s, String.length(p)), s)

def b2(+s: String, +p: String) -> String:
  Bool.pick(String, String.starts_with(s, p), String.drop(s, String.length(p)), String.concat([s, "!"]))

def b3(+nm: String, o: List<&2, String>) -> Bool:
  match o:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(h, nm), b3(nm, t))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
