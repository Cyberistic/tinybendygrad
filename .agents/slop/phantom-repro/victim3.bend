import Base
import ./sub.bend as Sub

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["victim3=", Bool.show(Sub.run())]))
