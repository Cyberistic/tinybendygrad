import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/tensor.bend as T
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/ops.bend as O

def ushow.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: ushow.go(t, String.concat([acc, U32.show(h), " "]))

def ushow(xs: List<&2, U32>) -> String:
  ushow.go(xs, "")

def strs.go(xs: List<&1, String>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: strs.go(t, String.concat([acc, h, ","]))

def strs(xs: List<&1, String>) -> String:
  strs.go(xs, "")

def go() -> IO(Unit):
  do IO<Unit>:
    a : String = String.trim_start(".x.", '.')
    IO.print(String.concat(["lstrip=[", a, "]"]))
    b : String = String.trim_end(".x.", '.')
    IO.print(String.concat(["rstrip=[", b, "]"]))
    c : List<&1, String> = String.split("a.b.c.", '.')
    IO.print(String.concat(["nsplit=", U32.show(U32.from_nat(List.length(&1, String, c)))]))
    d : String = String.join(["x", "y"], "-")
    IO.print(String.concat(["join=", d]))
    e : U32 = H.round_up_u32(11, 8)
    IO.print(String.concat(["ru=", U32.show(e)]))
    f : U32 = H.prod_u32([3, 4])
    IO.print(String.concat(["prod=", U32.show(f)]))
    g : List<&2, U32> = H.make_tuple_rep(5, 2)
    IO.print(String.concat(["mt=", ushow(g)]))
    h2 : List<&2, U32> = H.flatten_u32([[1,2],[3]])
    IO.print(String.concat(["flat=", ushow(h2)]))
    i : U32 = U32.from_nat(List.length(&2, U32, g))
    IO.print(String.concat(["len=", U32.show(i)]))
    j : String = String.concat(["q", U32.show(3), "."])
    IO.print(String.concat(["key=", j]))
    k : Bool = U32.is_eq(1, 1)
    IO.print(String.concat(["eq=", Bool.show(k)]))
    m : String = String.reverse("ab.c")
    IO.print(String.concat(["rev=", m]))
    n : List<&2, U32> = List.reverse(&2, U32, [7, 8, 9])
    IO.print(String.concat(["lrev=", ushow(n)]))

def main() -> IO(Unit):
  go()
