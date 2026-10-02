import Base

def p(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- p("f448", F32.show(F32.from_nat(448n)))
    p("f0", F32.show(F32.from_nat(0n)))
    p("f0", F32.show(F32.from_nat(0n)))
