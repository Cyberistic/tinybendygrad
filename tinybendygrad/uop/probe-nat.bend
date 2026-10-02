import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

def p(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- p("a", Nat.show(U32.to_nat(300)))
