# The `helpers.bend` floor-division bug, as a RUNNABLE REPRO. Kept because the
# report is only worth what a reader can re-run.
#
#   ./bin/bend .agents/slop/dm.bend
#
# LEFT COLUMN is `helpers.bend`. The expected answers, in the comment, are
# Python's. See also `dm-floor-probe.py`, which prints the same nine numbers from
# the Python side so the diff needs no mental arithmetic.
import Base
import ./../../tinybendygrad/helpers.bend as H

def a() -> U32: H.floordiv_i32(6, 4)            # 1   got 2
def b() -> U32: H.floordiv_i32(10, 3)           # 3   got 4
def c() -> U32: H.floordiv_i32(1000, 7)         # 142 got 143
def d() -> U32: H.floordiv_i32(10, 7)           # 1   got 2
def e() -> U32: H.floormod_i32(6, 4)            # 2   got -2 (4294967294)
def f() -> U32: H.floormod_i32(1000, 7)         # 6   got -1 (4294967295)
def g() -> U32: H.floordiv_i32(4294967289, 4)   # -2  CORRECT
def h() -> U32: H.floormod_i32(4294967289, 4)   # 1   CORRECT
def i() -> U32: H.floordiv_i32(4, 4)            # 1   CORRECT (exact)
def j() -> U32: H.cdiv_i32_go(6, 4)             # 1   CORRECT (truncating)

# THE ONE-LINE FIX, helpers.bend:1097. `floordiv_i32.trunc.exact`'s `False{}` arm
# adds one whenever the division is inexact and ignores `neg`; it must add one
# ONLY when `neg`. Stated here so the report and the patch cannot drift apart.

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(a()))
    IO.print(U32.show(b()))
    IO.print(U32.show(c()))
    IO.print(U32.show(d()))
    IO.print(U32.show(e()))
    IO.print(U32.show(f()))
    IO.print(U32.show(g()))
    IO.print(U32.show(h()))
    IO.print(U32.show(i()))
    IO.print(U32.show(j()))
