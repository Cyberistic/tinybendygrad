import Base
def le(x: U32, y: U32) -> Bool: Bool.and(U32.is_ge(x, y), U32.is_lt(x, y))
def hit(x: U32, lo: U32, hi: U32) -> Bool: U32.and(1u32, 1u32)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(le(2,3)))
