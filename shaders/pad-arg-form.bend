# shaders/pad-arg-form.bend -- THE MEASUREMENT BEHIND A CLAIM IN `shader.bend`.
#
# `mxw_pad` takes upstream's PAIR form `(offset, END)` where `END = s + before + after`, and
# NOT the after-amounts. Passing after-amounts is a mistake this folder MADE and nearly wrote
# up as a port defect: the fold correctly rejected `0 + 16 <= 1` and reported an unknown
# dtype, which reads exactly like a broken PAD arm.
#
# THE TWO ROWS ARE THE WHOLE ARGUMENT. On a `(16,16)` f32 buffer, padding one column:
#   after-amount  1       -> `?`      (the fold says the END is not past the offset)
#   END           17      -> `f32`    (the fold accepts it)
#
# IT IS A MEASUREMENT AND NOT A GATE: it asserts nothing, it prints three dtypes for a
# reader. The
# gate is `shader-gate.py`, which would not have caught this -- both sides would have had to
# be given the same wrong call -- which is why the measurement is kept as text.

import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/uop/render.bend as R
import ../tinybendygrad/LAWS/spec.bend as S
import ../tinybendygrad/tensor.bend as T
import ../tinybendygrad/mixin/creation.bend as CR
import ../tinybendygrad/mixin/movement.bend as MX

def dt_of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: R.dt_repr(d)
    case None{}: "?"

def rows() -> List<&2, String>:
  +ar = O.Arena.empty()
  +t = CR.cr_empty(ar, Some{S.single()}, [16, 16], S.D1{0})
  [String.concat(["after_amount=", dt_of(T.tn_dtype(MX.mxw_pad(t, [0, 0], [0, 1])))]),
   String.concat(["end=", dt_of(T.tn_dtype(MX.mxw_pad(t, [0, 0], [16, 17])))]),
   String.concat(["shrink=", dt_of(T.tn_dtype(MX.mxw_shrink(t, [0, 1], [16, 16])))])]

def put(rs: List<&2, String>) -> IO(Unit):
  match rs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +r <> rest:
      do IO<Unit>:
        a : Unit <- IO.print(r)
        b : Unit <- put(rest)
        IO.pure(Unit, b)

def main() -> IO(Unit): put(rows())
