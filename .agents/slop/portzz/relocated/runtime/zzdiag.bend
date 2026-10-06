import Base

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def NLCH() -> Char: Maybe.default(&2, Char, String.get("\n", 0n), ' ')
def S() -> String: "bendexec1 13 3\n1: PARAM f32 k:param:4:g\n2: PARAM f32 k:param:4:g\n"

def f(i: Nat) -> IO(Unit):
  row("fld", Maybe.default(&2, String, List.get(&2, String, String.split(S(), NLCH()), i), ""))

def go() -> IO(Unit):
  do IO<Unit>:
    row("n_split", U32.show(U32.from_nat(List.length(&2, String, String.split(S(), NLCH())))))
    f(0n)
    f(1n)
    f(2n)
    f(3n)

def main() -> IO(Unit): go()
