# THE PORT-SIDE PROBE. IT IMPORTS THE SCRATCH COPY OF THE PORT AND ASKS THE
# PORT'S OWN DEFS, PER CASE:
#
#   1. `nn_dot.xshape(xs, k)` -- THE RESHAPE TARGET CPYTHON BUILDS AT op.py:390.
#   2. `nn_dot.wshape(ws, k)` -- THE RESHAPE TARGET CPYTHON BUILDS AT op.py:391.
#   3. `nn_dot.order(len, dw)` -- CPYTHON'S `.transpose(-1, axis_w)`.
#   4. `nn_dot.rd(ax, bw)`   -- THE PORT'S OWN REFUSAL PREDICATE.
#   5. `nn_dot(x, w)`        -- THE RESULT.
#
# `probe_fix.bend` IS THIS FILE WITH ONE LINE CHANGED (THE IMPORT PATH).
#
# THE RESULT COLUMN HAS THREE VALUES, AND THE DIFFERENCE BETWEEN TWO OF THEM
# IS THE WHOLE POINT:
#   * A SHAPE      -- THE PORT ANSWERED.
#   * `NONE`       -- THE PORT REFUSED (`nn_dot` ANSWERED `None`).
#   * `<DEAD>`     -- THE PORT BUILT A GRAPH WHOSE SHAPE DOES NOT FOLD. THAT IS
#                     NOT A REFUSAL: IT IS A WRONG GRAPH HANDED BACK AS IF IT
#                     WERE AN ANSWER.
#
# `import Base` IS HERE SO `String`/`IO`/`U32` RESOLVE IN THIS FILE.

import Base
import ./scratchgw/nn/layers.bend as L
import ./scratchgw/mixin/movement.bend as MX
import ./scratchgw/tensor.bend as T

def p(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, " = ", MX.mx_show(xs)]))

def bs(b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"

def ans_s(s: List<&2, U32>) -> String:
  match s:
    case Nil{}: "<DEAD>"
    case _: MX.mx_show(s)

def ans_shp(ms: Maybe<&2, List<&2, U32>>) -> String:
  match ms:
    case Some{s}: ans_s(s)
    case None{}: "<UNREADABLE>"

def ans_t(+t: T.Tensor) -> String: ans_shp(L.nn_shape(t))

def ans(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: ans_t(t)
    case None{}: "NONE"

def one(+nm: String, +xs: List<&2, U32>, +ws: List<&2, U32>, xsz: U32, wsz: U32) -> IO(Unit):
  +dx = U32.from_nat(List.length(&2, U32, xs))
  +dw = U32.from_nat(List.length(&2, U32, ws))
  +k = L.nn_dotk(dx, dw)
  +xs2 = L.nn_dot.xshape(xs, k)
  +ws2 = L.nn_dot.wshape(ws, k)
  do IO<Unit>:
    p(String.concat([nm, "_xshape"]), xs2)
    p(String.concat([nm, "_wshape"]), ws2)
    p(String.concat([nm, "_order"]), L.nn_dot.order(L.nn_len32(ws2), dw))
    IO.print(String.concat([nm, "_rd = ", bs(L.nn_dot.rd(xs, ws))]))
    IO.print(String.concat([nm, "_result = ", ans(L.nn_dot(L.nn_row.t(xs, 0, xsz), L.nn_row.t(ws, 1, wsz)))]))

def main() -> IO(Unit):
  do IO<Unit>:
    # A: x(2,3) . w(3,4)    dw=2  CPython (2,4)
    one("A", [2, 3], [3, 4], 6, 12)
    # B: x(2,4,3) . w(3,4)  dw=2  CPython (2,4,4)
    one("B", [2, 4, 3], [3, 4], 24, 12)
    # C: x(8,64,7,7) . w(7,16)  dw=2  CPython (8,64,7,16)
    one("C", [8, 64, 7, 7], [7, 16], 25088, 112)
    # D: x(2,3) . w(3,)      dw=1  CPython (2,)
    one("D", [2, 3], [3], 6, 3)
    # P: x(2,3) . w(4,5)    dw=2  CPython REFUSES (GUARD: 3 != 4)
    one("P", [2, 3], [4, 5], 6, 20)
    # E: x(2,3,4) . w(3,4,5) dw=3 CPython REFUSES (BROADCAST)
    one("E", [2, 3, 4], [3, 4, 5], 24, 60)
    # F: x(2,3,4) . w(3,4,1) dw=3 CPython REFUSES (BROADCAST)
    one("F", [2, 3, 4], [3, 4, 1], 24, 12)
    # G: x(3,3,4) . w(3,4,1) dw=3 CPython ACCEPTS (3,3,1)
    one("G", [3, 3, 4], [3, 4, 1], 36, 12)
    # H: x(3,3,4) . w(3,5,1) dw=3 CPython REFUSES (GUARD: 4 != 5)
    one("H", [3, 3, 4], [3, 5, 1], 36, 15)
    # I: x(3,3,4) . w(3,4,2) dw=3 CPython ACCEPTS (3,3,2)
    one("I", [3, 3, 4], [3, 4, 2], 36, 24)
    # M: x(2,2,4) . w(3,3,4,5) dw=4 CPython REFUSES (BROADCAST)
    one("M", [2, 2, 4], [3, 3, 4, 5], 16, 180)
    # N: x(2,4) . w(3,3,4,5) dw=4 CPython ACCEPTS (3,3,2,5)
    one("N", [2, 4], [3, 3, 4, 5], 8, 180)
    # O: x(2,4) . w(3,3,5,5) dw=4 CPython REFUSES (GUARD: 4 != 5)
    one("O", [2, 4], [3, 3, 5, 5], 8, 225)
