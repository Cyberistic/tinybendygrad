# T3 -- what is List.sort's RESULT type?  The signature says List<A> (= List<&1,A>)
# and the body returns List<&2,A>; can the result be bound to a List<&2,String>?
import Base

def srt(xs: List<&2, String>) -> List<&2, String>:
  List.sort(~String, ~String.is_lt, xs)

def main() -> IO(Unit):
  do IO<Unit>:
    a : List<&2, String> <- IO.pure(List<&2, String>, srt(["b", "a", "c"]))
    IO.print(String.join(a, ","))
    IO.print("")
