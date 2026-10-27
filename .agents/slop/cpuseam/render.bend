# render.bend -- THE PORT's C RENDERER, RUN ON THE ORACLE's UOP LIST.
#
#   ./bin/bend .agents/slop/cpuseam/render.bend r_56_7_2_2
#
# IT READS THE KERNEL NAME FROM THE COMMAND LINE, RENDERS IT WITH THE PORT's
# OWN `cstyle.bend` (`C.render`), AND PRINTS THE C ON STDOUT. THE DRIVER
# (`.agents/slop/cpuseam/drive.py`) CAPTURES IT INTO
# `.agents/slop/cpuseam/out/<name>.c`.
#
# THE ORACLE IS `.agents/slop/cpuseam/csrc/<name>.c` -- UPSTREAM's OWN
# `ClangRenderer` OUTPUT FOR THE SAME UOP LIST. THE COMPARER IS
# `.agents/slop/cpuseam/diff.py`, AND IT COMPARES WHOLE FILES.
import Base
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./gen/r_10_98_4.bend as K0
import ./gen/r_2_14_14_4_4_3_3.bend as K1
import ./gen/r_4_28_7_4_3_3.bend as K2
import ./gen/r_56_14_2_2.bend as K3
import ./gen/r_56_7_2_2.bend as K4

def nth.go(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: ""

def nth(xs: List<&1, String>, k: Nat) -> String:
  nth.go(List.get(&1, String, xs, k))

def kus_of(nm: String) -> List<&2, C.KU>:
  match nm:
    case "r_10_98_4": K0.kus()
    case "r_2_14_14_4_4_3_3": K1.kus()
    case "r_4_28_7_4_3_3": K2.kus()
    case "r_56_14_2_2": K3.kus()
    case "r_56_7_2_2": K4.kus()
    case _: Nil{}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    nm : String = nth(args, 1n)
    src : String = C.render(C.dev_clang(), True{}, kus_of(nm))
    IO.print(src)
