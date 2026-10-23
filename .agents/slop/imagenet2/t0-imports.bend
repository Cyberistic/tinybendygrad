# T0 -- can a module import BOTH the datasets package alias `D` and sz.bend?
# The concern: sz.bend declares the constructor `D{full, rel}` and Bend shares ONE
# constructor namespace across modules, so `D` is both a module alias here and a
# constructor there.
import Base
import ../../../tinybendygrad/extra/datasets/__init__.bend as D
import ../../../tinybendygrad/sz.bend as SZ

def refused.at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

def main() -> IO(Unit):
  do IO<Unit>:
    r : D.Refused <- IO.pure(D.Refused, D.refuse("t0"))
    IO.print(String.concat(["refused=", refused.at(r)]))
    names : List<String> <- SZ.Sz.read_dir("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
    IO.print(String.concat(["read_dir_len=", Nat.show(List.length(&1, String, names))]))
    d : U32 <- SZ.Sz.is_dir("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
    IO.print(String.concat(["is_dir=", U32.show(d)]))
    IO.print("")
