import Base

def b1(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc, List.append(&2, Char, acc, [c]))

def b2(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc, List.append(&2, Char, acc, [c]))

def b3(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc, List.append(&2, Char, acc, [c]) <> b3(t, acc))

def b4(+cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc, List.append(&2, Char, acc, [c]) <> b4(t, acc))

def show(+cs: List<&2, Char>) -> String: String.from_list(cs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([show(b1(String.to_list("ab cd"), Nil{})), "|", show(b2(String.to_list("ab cd"), Nil{})),
      "|", show(b3(String.to_list("ab cd"), Nil{})), "|", show(b4(String.to_list("ab cd"), Nil{}))]))
