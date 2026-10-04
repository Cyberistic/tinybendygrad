import Base
import ./sub.bend as Sub

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["victim4=", Bool.show(Sub.run())]))
