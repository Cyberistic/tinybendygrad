import Base
def show64(x: I64) -> String: I64.show(x)
def neg64(x: I64) -> I64: I64.neg(x)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show64(neg64(1i64)))
