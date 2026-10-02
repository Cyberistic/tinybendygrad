import Base
def kp(+c: U32) -> Bool:
  Bool.or(Bool.or(U32.is_ge(c, 48), U32.is_le(c, 57)),
    Bool.or(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)),
      Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), U32.is_eq(c, 95))))
def code.go(+cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}   : 0
    case c <> +t : Char.to_u32(c)
def code(s: String) -> U32: code.go(String.to_list(s))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([U32.show(code(" ")), " ", U32.show(code("a")), " ", U32.show(code("$")), " ",
      Bool.pick(String, kp(code(" ")), "K32", "-"), " ",
      Bool.pick(String, kp(code("a")), "K97", "-"), " ",
      Bool.pick(String, kp(code("$")), "K36", "-"), " ",
      Bool.pick(String, kp(code("A")), "K65", "-"), " ",
      Bool.pick(String, kp(code("5")), "K53", "-")]))