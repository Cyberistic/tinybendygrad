# THE `helpers.bend` div/mod gate. Every row is compared against CPython, not
# against this port's own opinion of itself -- the diff IS the test:
#
#   .venv/bin/python .agents/slop/tools/dm-floor-gate.sh
#
# which runs this file in both lanes, runs `.agents/slop/dm-floor-probe.py` (the
# oracle: `tinygrad.helpers`' own `floordiv`/`floormod`/`cdiv`/`cmod`/`ceildiv`/
# `round_up`/`round_down`), and diffs. Both sides print `name=<u32>`, so the
# comparison needs no mental arithmetic and no sign convention: the Python side
# prints `v & 0xFFFFFFFF`, which is the same bit pattern a U32 holds.
#
# WHY THE TWO PREFIXES. `ok_` rows must match the oracle and do. `bad_` rows are
# KNOWN WRONG and are printed so the gate names its own remaining hole instead of
# hiding it: `ceildiv_i32` is `-(floordiv(-num, -amt))` where helpers.py:68 says
# `-(num // -amt)`, so it negates BOTH operands and answers -2 for
# `ceildiv(10,4)`. That is a separate defect from the `floordiv_i32` one fixed
# here, it is a one-line fix in the same block, and it is not in the remit this
# gate was written for -- so it is pinned as `bad_` rather than quietly dropped.
# When it is fixed these become `ok_` rows and the oracle stops disagreeing.
#
# The pair question, for the next agent: `cdiv_i32_go`/`cmod_i32` are the
# TRUNCATING pair (helpers.py:73-74, C semantics) and `floordiv_i32`/
# `floormod_i32` are the FLOOR pair (helpers.py:76-77, Python's `//` and `%`).
# Both are correct. `ceildiv` and `round_up` need the FLOOR pair and cannot be
# spelled with the truncating one -- measured, in helpers.bend's own comment.
import Base
import ./../../tinybendygrad/helpers.bend as H

def p(nm: String, n: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(n)]))

def main() -> IO(Unit):
  do IO<Unit>:
    # --- floordiv: the same-sign inexact rows are the ones the `neg` bug hit ---
    p("ok_fd_6_4", H.floordiv_i32(6, 4))
    p("ok_fd_10_3", H.floordiv_i32(10, 3))
    p("ok_fd_1000_7", H.floordiv_i32(1000, 7))
    p("ok_fd_10_7", H.floordiv_i32(10, 7))
    p("ok_fd_4_4", H.floordiv_i32(4, 4))
    p("ok_fd_0_7", H.floordiv_i32(0, 7))
    p("ok_fd_7_0", H.floordiv_i32(7, 0))
    p("ok_fd_4294967289_4", H.floordiv_i32(4294967289, 4))
    p("ok_fd_7_4294967292", H.floordiv_i32(7, 4294967292))
    p("ok_fd_4294967289_4294967292", H.floordiv_i32(4294967289, 4294967292))
    p("ok_fd_4294967292_4", H.floordiv_i32(4294967292, 4))
    p("ok_fd_4294967295_2", H.floordiv_i32(4294967295, 2))
    p("ok_fd_1_2", H.floordiv_i32(1, 2))
    p("ok_fd_2147483647_2", H.floordiv_i32(2147483647, 2))
    p("ok_fd_2147483648_1", H.floordiv_i32(2147483648, 1))
    # --- floormod, which is `x - floordiv(x,y)*y` and so inherits every row ---
    p("ok_fm_6_4", H.floormod_i32(6, 4))
    p("ok_fm_10_3", H.floormod_i32(10, 3))
    p("ok_fm_1000_7", H.floormod_i32(1000, 7))
    p("ok_fm_10_7", H.floormod_i32(10, 7))
    p("ok_fm_4_4", H.floormod_i32(4, 4))
    p("ok_fm_0_7", H.floormod_i32(0, 7))
    p("ok_fm_7_0", H.floormod_i32(7, 0))
    p("ok_fm_4294967289_4", H.floormod_i32(4294967289, 4))
    p("ok_fm_7_4294967292", H.floormod_i32(7, 4294967292))
    p("ok_fm_4294967289_4294967292", H.floormod_i32(4294967289, 4294967292))
    p("ok_fm_4294967292_4", H.floormod_i32(4294967292, 4))
    p("ok_fm_4294967295_2", H.floormod_i32(4294967295, 2))
    p("ok_fm_1_2", H.floormod_i32(1, 2))
    p("ok_fm_2147483647_2", H.floormod_i32(2147483647, 2))
    p("ok_fm_2147483648_1", H.floormod_i32(2147483648, 1))
    # --- the TRUNCATING pair, which was always right: the control that says
    # --- the sign matrix above is a real test and not a restatement.
    p("ok_cd_6_4", H.cdiv_i32_go(6, 4))
    p("ok_cd_4294967289_4", H.cdiv_i32_go(4294967289, 4))
    p("ok_cd_7_4294967292", H.cdiv_i32_go(7, 4294967292))
    p("ok_cd_4294967289_4294967292", H.cdiv_i32_go(4294967289, 4294967292))
    p("ok_cd_7_0", H.cdiv_i32_go(7, 0))
    p("ok_cm_6_4", H.cmod_i32(6, 4))
    p("ok_cm_4294967289_4", H.cmod_i32(4294967289, 4))
    p("ok_cm_7_4294967292", H.cmod_i32(7, 4294967292))
    p("ok_cm_7_0", H.cmod_i32(7, 0))
    # --- round_up/round_down CALL floordiv_i32, so they moved when it was fixed:
    # --- `round_up_i32(10,4)` answered 16 where helpers.py:69 says 12.
    p("ok_ru_10_4", H.round_up_i32(10, 4))
    p("ok_ru_10_3", H.round_up_i32(10, 3))
    p("ok_ru_1000_7", H.round_up_i32(1000, 7))
    p("ok_ru_4294967286_4", H.round_up_i32(4294967286, 4))
    p("ok_ru_4294967289_3", H.round_up_i32(4294967289, 3))
    p("ok_rd_10_4", H.round_down_i32(10, 4))
    p("ok_rd_4294967286_4", H.round_down_i32(4294967286, 4))
    p("ok_rd_1000_7", H.round_down_i32(1000, 7))
    # --- KNOWN WRONG, pinned rather than hidden. See the header.
    p("bad_ceil_10_4", H.ceildiv_i32(10, 4))
    p("bad_ceil_10_3", H.ceildiv_i32(10, 3))
    p("bad_ceil_1000_7", H.ceildiv_i32(1000, 7))
    p("bad_ceil_4294967286_4", H.ceildiv_i32(4294967286, 4))
