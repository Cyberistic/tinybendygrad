import Base
import ./substrate.bend as Sub

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["port=", Bool.show(Sub.answer())]))
