import Base

def probe_join() -> String: String.join(["a", "b", "c"], ",")
def probe_concat() -> String: String.concat(["x", "y"])
def probe_split() -> List<&2, String>: String.split("a,b,c", ',')
def probe_len() -> Nat: String.length("abc")
def probe_take() -> String: String.take("abcde", 2n)
def probe_drop() -> String: String.drop("abcde", 2n)
def probe_get() -> Maybe<&2, Char>: String.get("abc", 1n)
def probe_u32show() -> String: U32.show(42)
def probe_trim() -> String: String.trim("  a  ")
def probe_begins() -> Bool: String.starts_with("abc", "ab")
def probe_find() -> Nat: 0n
def probe_eq() -> Bool: String.eq("a", "a")
def probe_upper() -> String: String.to_upper("abc")
def probe_reverse() -> String: String.reverse("abc")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("join=" ++ probe_join())
    IO.print("concat=" ++ probe_concat())
    IO.print("split.len=" ++ Nat.show(List.length(&2, String, probe_split())))
    IO.print("len=" ++ Nat.show(probe_len()))
    IO.print("take=" ++ probe_take())
    IO.print("drop=" ++ probe_drop())
    IO.print("u32show=" ++ probe_u32show())
    IO.print("trim=" ++ probe_trim())
    IO.print("begins=" ++ Bool.show(probe_begins()))
    IO.print("eq=" ++ Bool.show(probe_eq()))
    IO.print("upper=" ++ probe_upper())
    IO.print("rev=" ++ probe_reverse())
