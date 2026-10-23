# T6 -- char literals in match cases, and '\t' style escapes.
import Base

def kind(c: Char) -> String:
  match c:
    case '"': "quote"
    case '\t': "tab"
    case '\n': "nl"
    case _: "other"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(kind('"'))
    IO.print(kind('\t'))
    IO.print(kind('\n'))
    IO.print(kind('x'))
    IO.print("")
