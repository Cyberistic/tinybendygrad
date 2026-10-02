import Base
def a(x: U32, y: U32) -> Bool: U32.is_eq(x, y)
def t1(x: U32, y: U32) -> U32:
  if U32.is_eq(x, y): 1
  else 2
def t2(x: U32, y: U32, b: Bool) -> U32:
  if b: 1
  else 2
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(t1(1,2)))
    IO.print(U32.show(t2(1,2,True{})))
