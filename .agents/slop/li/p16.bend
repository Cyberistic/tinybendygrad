import Base
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([U32.show(U32.div(44, 2)), "/", U32.show(U32.mod(44, 2))]))
