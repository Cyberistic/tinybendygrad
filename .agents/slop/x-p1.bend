import Base

def main() -> IO(Unit):
  do IO<Unit>:
    m : Map<String, U32> = Map.set(Map.set(Map.empty(), "BOOL", 0), "I8", 1)
    IO.print(String.concat(["len=", U32.show(U32.from_nat(Map.length(m)))]))
    ks : List<&1, String> = Map.keys(&1, U32, m)
    IO.print(String.concat(["keys=", ks.to_string()]))
    vs : List<&1, U32> = Map.values(&1, U32, m)
    IO.print(String.concat(["vals=", vs.to_string()]))
    s : Maybe<&2, U32> = Map.get(m, "I8")
    match s:
      case Some{v}: IO.print(String.concat(["I8=", U32.show(v)]))
      case None{}: IO.print("I8=None")
    keys : List<&1, String> = String.split("a.b.", '.')
    IO.print(String.concat(["split=", keys.to_string()]))
    IO.print(String.concat(["trim=[", String.trim("  ab  "), "]"]))
    IO.print(String.concat(["to_list=", String.to_list(".x.").to_string()]))
    IO.print(String.concat(["dot=", U32.show(Char.to_u32(Char.from_u32(46)))]))
    IO.print(String.concat(["sw=", Bool.show(String.starts_with("ab.", "ab"))]))
    IO.print(String.concat(["rev=", String.reverse("a.b.")]))
    IO.print(String.concat(["len3=", U32.show(U32.from_nat(String.length("a.b.")))]))
