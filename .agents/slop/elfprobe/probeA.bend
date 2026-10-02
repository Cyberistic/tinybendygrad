import Base
def StrAt(fuel: Nat, byte_at: U32, +h: String) -> String:
  StrAt.at(fuel, byte_at, h, "")
def StrAt.at(fuel: Nat, +idx: U32, +h: String, +acc: String) -> String:
  match fuel:
    case 0n: acc
    case Succ{q}: StrAt.at(q, U32.add(idx, 1), h, String.concat([acc, "x"]))
def tab(+h: String, +tbl_off: U32, +byte_at: U32) -> String:
  StrAt(1n, byte_at, h)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(tab("abc", 0, 1))
