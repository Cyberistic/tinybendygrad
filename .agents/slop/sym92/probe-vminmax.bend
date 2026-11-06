import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/uop/symbolic.bend as SY

# DOES THE PORT's `F.UOp.vmin`/`F.UOp.vmax` MATCH UPSTREAM's `_min_max`? THE CPYTHON HALF IS
# probe-vminmax.py.
#
# THIS IS THE LAST OF THE THREE WALLS THE `divandmod.bend` TODO BLOCK NAMES. THE OTHERS ARE
# `divides` (MEASURED: THE PORT'S ANSWERS THE SAME AS UPSTREAM'S, SO THAT WALL IS STALE) AND
# `const_factor` (THE PORT HAS A FULL GCD FOLD AT `ops.bend:7855`). THE `_min_max` WALL IS THE
# ONE THAT GATES `fold_divmod_congruence`, `nest_by_factor` AND `factor_remainder`.
#
# UPSTREAM'S ANSWERS, MEASURED 2026-11-06:
#   x[0..10]      y[-5..5]      x*4[0..40]     x+y[-5..15]    x*4+8[8..48]

def sx.bnd2(b: Maybe<&2, F.Bnd>, d: String) -> String:
  match b:
    case Some{v}: H.i64_dec(SY.bnd_i64(v))
    case None{}: d

def sx.bnd(b: Maybe<&2, F.Bnd>) -> String:
  sx.bnd2(b, "none")


def sx.pair(+ar: O.Arena, +bt: F.BTable, +u: U32) -> String:
  String.concat(["[", sx.bnd(F.UOp.vmin(ar, bt, u)), "..", sx.bnd(F.UOp.vmax(ar, bt, u)), "]"])

def rows() -> String:
  +x = O.UOp.variable(O.Arena.empty(), "x", H.i64_of_i32(0), H.i64_of_i32(10), 1, S.weakint())
  +y = O.UOp.variable(O.Found.ar(x), "y", H.i64_neg(True{}, H.i64_of_i32(5)), H.i64_of_i32(5), 2, S.weakint())
  +c4 = O.UOp.const(O.Found.ar(y), O.CInt{H.i64_of_i32(4)})
  +m4 = O.UOp.alu(O.Found.ar(c4), O.OpsMUL{}, [O.Found.i(x), O.Found.i(c4)])
  +c8 = O.UOp.const(O.Found.ar(m4), O.CInt{H.i64_of_i32(8)})
  +a8 = O.UOp.alu(O.Found.ar(c8), O.OpsADD{}, [O.Found.i(m4), O.Found.i(c8)])
  +s = O.UOp.alu(O.Found.ar(a8), O.OpsADD{}, [O.Found.i(x), O.Found.i(y)])
  +bt = F.mm.sweep(O.Found.ar(s), F.Folded.t(F.folded(O.Found.ar(s))))
  String.concat(["x=", sx.pair(O.Found.ar(s), bt, O.Found.i(x)), "\n",
                 "y=", sx.pair(O.Found.ar(s), bt, O.Found.i(y)), "\n",
                 "x*4=", sx.pair(O.Found.ar(s), bt, O.Found.i(m4)), "\n",
                 "x+y=", sx.pair(O.Found.ar(s), bt, O.Found.i(s)), "\n",
                 "x*4+8=", sx.pair(O.Found.ar(s), bt, O.Found.i(a8)), "\n"])

def main() -> String: rows()
