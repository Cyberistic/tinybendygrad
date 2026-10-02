import Base
def t(b: Bool) -> String: Bool.pick(String, b, "yes", "no")
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([t(String.contains("EnumBitField(1, 2)", "EnumBitField")), "/",
      t(String.contains("EnumBitField", "EnumBitField(1, 2)"))]))
