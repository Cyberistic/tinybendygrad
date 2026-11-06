import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/dtype.bend as D

# DOES THE PORT's `UOp.divides` MATCH UPSTREAM's? THE CPYTHON HALF IS probe-divides.py.
#
# THIS IS THE MEASUREMENT THAT THE `divandmod.bend` TODO BLOCK NEEDS: IT SAYS THE WALL FOR
# `nested_div` AND `remove_nested_mod` IS "`divides` NEEDS `gcd` NEEDS A `Counter` FOLD", BUT
# THE PORT's `UOp.divides` (`ops.bend:7972`) IS A RECURSION OVER ADD/MUL/CONST THAT CARRIES A
# `Dv` RECORD -- SO IF IT ANSWERS THE SAME AS UPSTREAM, THAT WALL IS STALE.
#
# UPSTREAM'S ANSWERS, MEASURED 2026-11-06:
#   (x*4).divides(4)    = MUL(x, 1)
#   (x*4+8).divides(4)  = ADD(MUL(x, 1), 2)
#   (x*6).divides(4)    = None
#   x.divides(4)        = None

def sx.pname(m: Maybe<&2, String>) -> String:
  match m:
    case Some{n}: n
    case None{}: "?"

def sx.cval.of(a: O.Arg) -> O.Const:
  match a:
    case O.APy{v}: v
    case _: O.CInvalid{}

def head.of(a: O.Arg, op: O.Op) -> String:
  match a:
    case O.ADt{dt}: String.concat([O.Ops.name.of(op), ":", D.dt_name(dt)])
    case O.AParam{pa}: sx.pname(O.ParamArg.name(pa))
    case _: O.Ops.name.of(op)

def sx.const.of(c: O.Const) -> String:
  match c:
    case O.CInt{i}: H.i64_text(i)
    case _: "bad"

def sx.of(+op: O.Op, +a: O.Arg) -> String:
  match op:
    case O.OpsCONST{}: sx.const.of(sx.cval.of(a))
    case _: head.of(a, op)

def sx.at(+u: U32, +ar: O.Arena) -> String:
  sx.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

def sx.ans2(ok: Bool, +f: O.Found) -> String:
  match ok:
    case True{}: sx.at(O.Found.i(f), O.Found.ar(f))
    case False{}: "none"

def sx.ans3(d: O.Dv) -> String:
  match d:
    case O.Dv{ok, f, i}: sx.ans2(ok, f)

# THE QUOTIENT'S OWN LEAVES, so a RIGHT SHAPE WITH A WRONG QUOTIENT SHOWS.
def sx.leaves2(t: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match t:
    case Nil{}: acc
    case s <> r: sx.leaves2(r, ar, String.concat([acc, sx.at(s, ar), " "]))

def sx.leaves(+u: U32, +ar: O.Arena, acc: String) -> String:
  sx.leaves2(O.Arena.srcs(ar, u), ar, acc)

def sx.full2(ok: Bool, +f: O.Found) -> String:
  match ok:
    case True{}: sx.leaves(O.Found.i(f), O.Found.ar(f), "")
    case False{}: "none"

def sx.full3(d: O.Dv) -> String:
  match d:
    case O.Dv{ok, f, i}: sx.full2(ok, f)

def sx.full(d: O.Dv) -> String:
  sx.full3(d)



def sx.ans(d: O.Dv) -> String:
  sx.ans3(d)

# THE RECORD IS READ TWICE, so it is DESTRUCTURED ONCE.


def rows() -> String:
  +x = O.UOp.variable(O.Arena.empty(), "x", H.i64_of_i32(0), H.i64_of_i32(10), 1, S.weakint())
  +c4 = O.UOp.const(O.Found.ar(x), O.CInt{H.i64_of_i32(4)})
  +m4 = O.UOp.alu(O.Found.ar(c4), O.OpsMUL{}, [O.Found.i(x), O.Found.i(c4)])
  +c8 = O.UOp.const(O.Found.ar(m4), O.CInt{H.i64_of_i32(8)})
  +a8 = O.UOp.alu(O.Found.ar(c8), O.OpsADD{}, [O.Found.i(m4), O.Found.i(c8)])
  +c6 = O.UOp.const(O.Found.ar(a8), O.CInt{H.i64_of_i32(6)})
  +m6 = O.UOp.alu(O.Found.ar(c6), O.OpsMUL{}, [O.Found.i(x), O.Found.i(c6)])
  +fu = O.Arena.budget(O.Found.ar(m6))
  String.concat(["x*4.divides(4)=", sx.ans(O.UOp.divides(fu, O.Found.ar(m4), H.i64_of_i32(4), O.Found.i(m4))), "\n",
                 "x*4+8.divides(4)=", sx.ans(O.UOp.divides(fu, O.Found.ar(a8), H.i64_of_i32(4), O.Found.i(a8))), "\n",
                 "x*6.divides(4)=", sx.ans(O.UOp.divides(fu, O.Found.ar(m6), H.i64_of_i32(4), O.Found.i(m6))), "\n",
                 "x.divides(4)=", sx.ans(O.UOp.divides(fu, O.Found.ar(x), H.i64_of_i32(4), O.Found.i(x))), "\n",
                 "LEAVES x*4+8: ", sx.full(O.UOp.divides(fu, O.Found.ar(a8), H.i64_of_i32(4), O.Found.i(a8))), "\n"])

def main() -> String: rows()
