import Base
import ./../../tinybendygrad/helpers.bend as H

# ilt.bend -- WHAT ORDER IS `U32.is_lt` IN? Measured, not read.
#
# `f2f-arena.bend` printed FORWARD on EVERY row, including `0 NOOP <- 0,0` and
# `1 PARAM <- 0,0`, which cannot be forward. So either the test is `is_lt(self, src)` and
# the flag is inverted, or `Bool.or` is not the disjunction it reads as. A flag that fires
# on every row is a flag that measures nothing, and it is exactly the shape of a gate that
# says PASS.
#
# agent-core.md: "An unexplained zero is still a zero." So is an unexplained TRUE.

def s(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["is_lt(3,5)=", s(U32.is_lt(3, 5)),
                            " is_lt(5,3)=", s(U32.is_lt(5, 3)),
                            " is_lt(5,5)=", s(U32.is_lt(5, 5)), "\n"]))
    IO.print(String.concat(["Bool.or(T,F)=", s(Bool.or(True{}, False{})),
                            " Bool.or(F,F)=", s(Bool.or(False{}, False{})),
                            " Bool.or(T,T)=", s(Bool.or(True{}, True{})), "\n"]))