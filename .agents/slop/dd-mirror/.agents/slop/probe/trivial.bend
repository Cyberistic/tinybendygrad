import Base

type S is Data:
  S{a: U32, b: String}

def mk(a: U32, b: String) -> S:
  S{a, b}

def twice(x: U32) -> U32:
  (x * 2 : U32)

def show2(a: U32, s: String) -> String:
  String.concat([U32.show(twice(a)), "/", s])

def main() -> IO(Unit):
  do IO<Unit>:
    s : String <- IO.pure(String, show2(7, "hi"))
    io : Unit <- IO.print(s)
    return io
