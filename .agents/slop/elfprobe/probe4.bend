import Base
def HEXDIGS() -> List<&2, Char>: String.to_list("0123456789abcdef")
def Hex.digit(i: Nat) -> String:
  String.from_list([Maybe.default(&2, Char, List.get(&2, Char, HEXDIGS, i), Char.from_u32(48))])
def Hex.byte(+v: U32) -> String:
  String.concat([Hex.digit(U32.to_nat(U32.shrn(v, 4n))), Hex.digit(U32.to_nat(v)), ""])
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Hex.byte(255))
    IO.print(Hex.byte(0))
