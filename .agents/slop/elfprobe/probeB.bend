import Base
def StrAt.at(fuel: Nat, +idx: U32, +h: String, +acc: String) -> String:
  match fuel:
    case 0n: acc
    case Succ{q}: StrAt.at(q, U32.add(idx, 1), h, String.concat([acc, "x"]))
def StrAt(fuel: Nat, byte_at: U32, +h: String) -> String:
  StrAt.at(fuel, byte_at, h, "")
def Blob.drop_to(+h: String, +off: U32) -> String: String.drop(h, U32.to_nat(U32.mul(off, 2)))
def Blob.take_n(+s: String, +n: U32) -> String: String.take(s, U32.to_nat(U32.mul(n, 2)))
def Blob.slice(+h: String, +off: U32, +n: U32) -> String: Blob.take_n(Blob.drop_to(h, off), n)
def Blob.hexlen(h: String) -> U32: U32.from_nat(String.length(h))
def Blob.nbytes(h: String) -> U32: U32.div(Blob.hexlen(h), 2)
def Blob.fuel(h: String) -> Nat: U32.to_nat(Blob.nbytes(h))
def Str.tab(+h: String, +tbl_off: U32, +byte_at: U32) -> String:
  StrAt(Blob.fuel(h), byte_at, Blob.slice(h, tbl_off, Blob.nbytes(h)))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Str.tab("abcdef", 1, 1))
