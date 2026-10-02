import Base

def a1(+a: String, +b: String, +c: String) -> Bool: Bool.or(String.eq(a, b), String.eq(a, c))
def a2(+a: String, +b: String) -> String: String.drop(a, String.length(b))
def a3(+a: String, +p: String) -> String:
  +hit = String.starts_with(a, p)
  String.drop(a, String.length(p))
def a4(a: String, p: String) -> String:
  match String.eq(a, p):
    case True{}: String.drop(a, 1n)
    case False{}: a
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("")
