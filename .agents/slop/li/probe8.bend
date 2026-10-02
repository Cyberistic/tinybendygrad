import Base
def x(a: U32, b: U32) -> U32: U32.sub(a, b)
def y(a: U32, s: String) -> Nat: U32.to_nat(U32.sub(a, U32.from_nat(String.length(s))))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(y(3, "ab")))
