import Base
import ../../../../tinybendygrad/device.bend as D
def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))
def main() -> IO(Unit):
  do IO<Unit>:
    +a : List<&2, U32> <- IO.pure(List<&2, U32>, D.iter_sig([8, 8, 8, 4, 4]))
    lrow("sig", a)
    +b : List<&2, U32> <- IO.pure(List<&2, U32>, D.iter_sig([1, 4, 2, 8, 4, 1]))
    lrow("mix", b)
    IO.print("done=1")
