import Base
def x(a: U32, b: U32) -> Nat: U32.to_nat(U32.sub(a, b))
def y(a: U32, s: String) -> Nat: U32.to_nat(U32.sub(a, String.length(s)))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(U32.to_nat(U32.sub(3, 2))))
