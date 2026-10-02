import Base
def c(a: String, b: String) -> Bool: String.contains(a, b)
def c.of(b: Bool) -> String: Bool.pick(String, b, "yes", "no")
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([c.of(c("EnumBitField(1, 2)", "EnumBitField")), "/", c.of(c("nope", "EnumBitField"))]))
