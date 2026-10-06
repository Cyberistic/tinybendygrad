import Base

def p(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p("r0", "0")
    b : Unit <- p("r1", NoSuchThing.boom())
    p("r2", "2")

def main() -> IO(Unit): rows()
