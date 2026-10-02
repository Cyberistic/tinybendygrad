import Base

def hx.d(c: Char) -> U32: Char.to_u32(c)
def hx.isdig(c: Char) -> Bool: Char.is_digit(c)
def hx.isupp(c: Char) -> Bool: Char.is_upper(c)
def hx.islow(c: Char) -> Bool: Char.is_lower(c)
def hx.any(+c: Char) -> Bool: Bool.or(hx.isdig(c), Bool.or(hx.isupp(c), hx.islow(c)))
def hx.v.d(c: Char) -> U32: hx.d(c)
def hx.v.l(c: Char) -> U32: U32.sub(hx.d(c), 87)
def hx.v.u(c: Char) -> U32: U32.sub(hx.d(c), 55)
def hx.v(+c: Char) -> U32:
  Bool.pick(U32, hx.isdig(c), hx.v.d(c),
    Bool.pick(U32, hx.islow(c), hx.v.l(c),
      Bool.pick(U32, hx.isupp(c), hx.v.u(c), 15)))

# THE BYTE LAYER. A blob is a hex String; `u8` is the byte at a byte offset.
def blob.nbytes(h: String) -> U32: U32.from_nat(String.length(h))
def blob.ch(h: String, i: U32) -> Char: Maybe.default(&2, Char, String.get(h, U32.to_nat(i)), Char.from_u32(48))
def blob.nib(h: String, i: U32) -> U32: hx.v(blob.ch(h, i))
def blob.u8(+h: String, +i: U32) -> U32:
  U32.add(U32.mul(blob.nib(h, U32.mul(i, 2)), 16), blob.nib(h, U32.add(U32.mul(i, 2), 1)))
def blob.le16(+h: String, +i: U32) -> U32:
  U32.add(blob.u8(h, i), U32.mul(blob.u8(h, U32.add(i, 1)), 256))
def blob.le32(+h: String, +i: U32) -> U32:
  U32.add(blob.le16(h, i), U32.mul(blob.le16(h, U32.add(i, 2)), 65536))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["v41=", U32.show(hx.v(Char.from_u32(65)))]))
    IO.print(String.concat(["v66=", U32.show(hx.v(Char.from_u32(102)))]))
    IO.print(String.concat(["v9=", U32.show(hx.v(Char.from_u32(57)))]))
    IO.print(String.concat(["nb=", U32.show(blob.nbytes("7f454c46"))]))
    IO.print(String.concat(["u8_0=", U32.show(blob.u8("7f454c46", 0))]))
    IO.print(String.concat(["u8_3=", U32.show(blob.u8("7f454c46", 3))]))
    IO.print(String.concat(["le16_4=", U32.show(blob.le16("0002000110010003", 4))]))
    IO.print(String.concat(["le32_4=", U32.show(blob.le32("00000000efbeadde", 4))]))
    IO.print(String.concat(["le32_0=", U32.show(blob.le32("efbeadde11223344", 0))]))
    IO.print("probe-done=1")
