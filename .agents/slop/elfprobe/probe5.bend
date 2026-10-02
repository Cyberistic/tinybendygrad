import Base
def j(x: U32) -> String: String.concat([U32.show(x), ","])
def f(x: Bool) -> String:
  Bool.pick(String, x,
    String.join([j(1), j(2)], ","),
    String.join([j(3), j(4)], ","))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(f(True{}))
