# read.bend -- READ A FILE, TO MEASURE THE JS LANE's STACK.
#
#   bun /tmp/read.js <path>
#
# IT READS THE FILE WITH THE PORT's OWN `H.lines` AND PRINTS THE LINE COUNT.
# THE POINT IS THE SIZE: THE SAME PROGRAM, THE SAME LINE, TWO FILES.
import Base
import ./../../../tinybendygrad/helpers.bend as H

def nth(xs: List<&1, String>, k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    nm : String = nth(args, 1n)
    ls : List<&2, String> <- H.lines(nm)
    IO.print(String.concat(["lines=", U32.show(U32.from_nat(List.length(&2, String, ls)))]))
