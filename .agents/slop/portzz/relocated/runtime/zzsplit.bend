import Base

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def NLCH() -> Char: Maybe.default(&2, Char, String.get("\n", 0n), ' ')

def parts() -> IO(Unit):
  do IO<Unit>:
    urow("p_split_nl_len", U32.from_nat(List.length(&2, String, String.split("a\nb\nc\n", NLCH()))))
    row("p_split_nl_join", String.join(String.split("a\nb\nc\n", NLCH()), "|"))

def chars() -> IO(Unit):
  do IO<Unit>:
    urow("p_to_list_len", U32.from_nat(List.length(&2, Char, String.to_list("a\nb\nc\n"))))
    row("p_char0", U32.show(Char.to_u32(Maybe.default(&2, Char, List.get(&2, Char, String.to_list("a\nb\nc\n"), 0n), ' '))))
    row("p_char1", U32.show(Char.to_u32(Maybe.default(&2, Char, List.get(&2, Char, String.to_list("a\nb\nc\n"), 1n), ' '))))

def go() -> IO(Unit):
  do IO<Unit>:
    row("p_join", String.join(["a", "b", "c"], "\n"))
    parts()
    chars()

def main() -> IO(Unit): go()
