import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# f2f-fixtures.bend -- the port side of `.agents/slop/f2f-fixtures.py`, the same seven
# `f2f` fixtures in the same order. This is the PROBE; the rows themselves land in
# `dtype.bend`'s `gate`, and this file is what measures them before they land.
#
# WHY SEVEN AND NOT THREE. Three reach only `f2f.up`'s ocp arm and `f2f.down`'s two
# narrowing arms. The other four are the only way into the rest of the region:
#
#   f1  fp8e4m3fnuz -> float32   dtype.py:108 `if fr in dtypes.fp8_fnuz` -- the ONLY
#                                 fixture that reaches `f2f.fnuz`, and `f2f.fnuz` is
#                                 one of the three defs Task A changed.
#   f2  float32 -> fp8e5m2fnuz   dtype.py:123 `if to in dtypes.fp8_fnuz` -- the ONLY
#                                 fixture that reaches `f2f.down.fnuz`.
#   x1  float16 -> bfloat16      dtype.py:125 `else: raise NotImplementedError`. A
#                                 NEGATIVE fixture: CPython RAISES and the port answers
#                                 `None`, and only a fixture that must FAIL can say so.
#   x2  float32 -> float64       a widening whose `mx` needs an `f64` CONST, so it is
#                                 the second arm of `f2f_clamp_max` (`c7`'s subject).
#
# BEND SHAPES, all measured: a `match` cannot scrutinise a computed value, so `f2f`'s
# `Maybe` answer arrives as a def PARAMETER; `+nm` and `+i` are LINEARITY.

type R is Data:
  R{ar: O.Arena, i: U32, m: Bool}

def miss(r: Maybe<&2, O.Found>, +ar: O.Arena) -> R:
  match r:
    case Some{+f}: R{O.Found.ar(f), O.Found.i(f), True{}}
    case None{}: R{ar, 0, False{}}

def w1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "w1", S.fp8e4m3())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.fp8e4m3(), S.single(), True{}), pa)

def n1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "n1", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e4m3(), True{}), pa)

def n2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "n2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e5m2(), True{}), pa)

def f1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "f1", S.fp8e4m3fnuz())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.fp8e4m3fnuz(), S.single(), True{}), pa)

def f2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "f2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e5m2fnuz(), True{}), pa)

def x1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "x1", S.half())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.half(), S.bfloat16(), True{}), pa)

def x2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "x2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.double(), True{}), pa)

# A REFUSAL PRINTS ITS REFUSAL, and the refusal name is dtype.py's EXCEPTION, not the
# port's own `None`. `f2f.sel2` answers 2 for "neither branch", and `f2f.sel`'s `_` arm
# maps that to `None{}`, so the port declines rather than raising. CPython raises
# `NotImplementedError` at dtype.py:125. Both are refusals of the same pair; the row says
# which one this is, and a fixture that printed nothing would say neither.
def one(+nm: String, r: R) -> IO(Unit):
  match r:
    case R{+ar, +i, m}:
      +fu = D.dd_fuel(ar)
      +cn = D.dd_cone(fu, ar, [i])
      do IO<Unit>:
        IO.print(String.concat([nm, "=", D.dd_tree(ar, i), "\n"]))
        IO.print(String.concat([nm, "n=", U32.show(O.Arena.next(ar)), "\n"]))
        IO.print(String.concat([nm, "sig=", D.dd_esig(ar, fu, cn, True{}, ""), "\n"]))
        IO.print(String.concat([nm, "k=", D.dd_eck(ar, fu, cn, True{}, ""), "\n"]))

def dd_reffn(built: Bool) -> String:
  match built:
    case True{}: "NotImplementedError"
    case False{}: "unported"

def ref(+nm: String, r: R) -> IO(Unit):
  match r:
    case R{+ar, +i, m}:
      do IO<Unit>:
        IO.print(String.concat([nm, "=refused:", dd_reffn(m), "\n"]))
        IO.print(String.concat([nm, "n=0\n"]))

def main() -> IO(Unit):
  +a1 = O.Arena.empty()
  +r1 = w1(a1)
  +a2 = O.Arena.empty()
  +r2 = n1(a2)
  +a3 = O.Arena.empty()
  +r3 = n2(a3)
  +a4 = O.Arena.empty()
  +r4 = f1(a4)
  +a5 = O.Arena.empty()
  +r5 = f2(a5)
  +a6 = O.Arena.empty()
  +r6 = x1(a6)
  +a7 = O.Arena.empty()
  +r7 = x2(a7)
  do IO<Unit>:
    one("w1", r1)
    one("n1", r2)
    one("n2", r3)
    one("f1", r4)
    one("f2", r5)
    ref("x1", r6)
    one("x2", r7)