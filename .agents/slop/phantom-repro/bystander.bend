import Base
import ./sub.bend as Sub

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["bystander=", Bool.show(Sub.run_unreachable())]))
