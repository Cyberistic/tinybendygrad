import Base
def u32str(v: U32) -> String: U32.show(v)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.join(&2, String, List.map(&2, U32, &2, String, u32str, [1,2,3]), ","))
