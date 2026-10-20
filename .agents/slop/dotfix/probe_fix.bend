# THE PORT-SIDE PROBE. IT IMPORTS THE SCRATCH COPY OF THE PORT AND ASKS
# THE PORT'S OWN DEFS THREE QUESTIONS PER CASE:
#
#   1. `nn_dot.xshape(xs, k)`  -- THE RESHAPE TARGET CPython BUILDS AT op.py:390.
#   2. `nn_dot.wshape(ws, k)`  -- THE RESHAPE TARGET CPYTHON BUILDS AT op.py:391.
#   3. `nn_dot(x, w)`          -- THE RESULT SHAPE, END TO END.
#
# THE ONLY LINE THAT DIFFERS FROM `probe_fix.bend` IS THE IMPORT PATH, AND
# `diff probe.bend probe_fix.bend` SAYS SO. THE BODY IS ONE COPY.
#
# THE INPUTS ARE THE SAME FIVE CASES AS `.agents/slop/dotfix/cpython_oracle.py`,
# AND THE CPython COLUMN OF `cases.rows` IS THAT FILE'S OUTPUT.

import ./scratchfix/nn/layers.bend as L
import ./scratchfix/mixin/movement.bend as MX

def p(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, " = ", MX.mx_show(xs)]))

def main() -> IO(Unit):
  do IO<Unit>:
    # A: x(2,3) . w(3,4)   CPython x'=(2,1,3)  w'=(1,3,4)  result (2,4)
    p("A_xshape", L.nn_dot.xshape([2, 3], 1))
    p("A_wshape", L.nn_dot.wshape([3, 4], 1))
    p("A_order ", L.nn_dot.order(3, 2))
    IO.print(String.concat(["A_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([2, 3], 0, 6), L.nn_row.t([3, 4], 1, 12)))]))

    # B: x(2,4,3) . w(3,4)  CPython x'=(2,4,1,3) w'=(1,3,4)  result (2,4,4)
    p("B_xshape", L.nn_dot.xshape([2, 4, 3], 1))
    p("B_wshape", L.nn_dot.wshape([3, 4], 1))
    p("B_order ", L.nn_dot.order(3, 2))
    IO.print(String.concat(["B_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([2, 4, 3], 0, 24), L.nn_row.t([3, 4], 1, 12)))]))

    # C: x(8,64,7,7) . w(7,16)  CPython x'=(8,64,7,1,7) w'=(1,7,16) result (8,64,7,16)
    p("C_xshape", L.nn_dot.xshape([8, 64, 7, 7], 1))
    p("C_wshape", L.nn_dot.wshape([7, 16], 1))
    p("C_order ", L.nn_dot.order(3, 2))
    IO.print(String.concat(["C_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([8, 64, 7, 7], 0, 25088), L.nn_row.t([7, 16], 1, 112)))]))

    # D: x(2,3) . w(3,)  CPython x'=(2,3) w'=(3,) result (2,)
    p("D_xshape", L.nn_dot.xshape([2, 3], 0))
    p("D_wshape", L.nn_dot.wshape([3], 0))
    p("D_order ", L.nn_dot.order(1, 1))
    IO.print(String.concat(["D_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([2, 3], 0, 6), L.nn_row.t([3], 1, 3)))]))

    # E: x(2,3,4) . w(3,4,5)  CPython x'=(2,3,1,4) w'=(3,1,4,5) -- CPython RAISES
    p("E_xshape", L.nn_dot.xshape([2, 3, 4], 1))
    p("E_wshape", L.nn_dot.wshape([3, 4, 5], 1))
    p("E_order ", L.nn_dot.order(6, 3))
    IO.print(String.concat(["E_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([2, 3, 4], 0, 24), L.nn_row.t([3, 4, 5], 1, 60)))]))

    # F: x(2,3,4) . w(3,4,1)  CPython x'=(2,3,1,4) w'=(3,1,4,1) result (2,3,1)
    p("F_xshape", L.nn_dot.xshape([2, 3, 4], 1))
    p("F_wshape", L.nn_dot.wshape([3, 4, 1], 1))
    p("F_order ", L.nn_dot.order(6, 3))
    IO.print(String.concat(["F_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([2, 3, 4], 0, 24), L.nn_row.t([3, 4, 1], 1, 12)))]))

    # G: x(3,3,4) . w(3,4,1)  CPython x'=(3,3,1,4) w'=(3,1,4,1) result (3,3,1)
    p("G_xshape", L.nn_dot.xshape([3, 3, 4], 1))
    p("G_wshape", L.nn_dot.wshape([3, 4, 1], 1))
    p("G_order ", L.nn_dot.order(6, 3))
    IO.print(String.concat(["G_result = ", L.nn_row.shp(L.nn_dot(L.nn_row.t([3, 3, 4], 0, 36), L.nn_row.t([3, 4, 1], 1, 12)))]))

    # THE GRAPH SIGNATURE OF THE 2-D CASE -- NODE COUNT, ROOT OP, OP SEQUENCE.
    IO.print(String.concat(["A_sig = ", L.nn_row.sig(L.nn_dot(L.nn_row.t([2, 3], 0, 6), L.nn_row.t([3, 4], 1, 12)))]))
