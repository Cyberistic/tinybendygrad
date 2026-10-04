import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/helpers.bend as H

# dd-bandarena.bend -- every SLOT of one `f2f` call's arena, so a wrong answer can be
# NAMED instead of guessed at. `dd-bandprobe.bend` answers `w1=BITCAST(C(-1))` with a
# TWO-node cone against CPython's 29, and a 2-node cone is a symptom, not a diagnosis:
# either the answer is a genuinely different node or the ROOT index points somewhere
# else. `O.Arena.node` is TOTAL -- it answers the arena bottom out of range -- so
# "reads back as NOOP" is a real failure mode here, and printing the arena is the only
# way to tell the two apart.
#
# SAME SHAPES AS dd-bandprobe.bend (a `match` may not scrutinise a computed value; `+nm`
# and `+i` are linearity; a `let` after an `IO` effect is refused).

type R is Data:
  R{ar: O.Arena, i: U32}

def miss(r: Maybe<&2, O.Found>, +ar: O.Arena) -> R:
  match r:
    case Some{+f}: R{O.Found.ar(f), O.Found.i(f)}
    case None{}: R{ar, U32.sub(O.Arena.next(ar), 1)}

def w1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v1", S.fp8e4m3())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.fp8e4m3(), S.single(), True{}), pa)

def mark(b: Bool) -> String:
  match b:
    case True{}: "ROOT"
    case False{}: ""

def slot.line(+root: U32, +i: U32, +ar: O.Arena) -> String:
  String.concat([U32.show(i), "\t", D.dd_sig1(ar, i), "\t", D.dd_lab(ar, i),
                 "\t<- ", D.dd_lab(ar, O.Arena.src0(ar, i)), ",", D.dd_lab(ar, O.Arena.src(ar, i, 1)),
                 "\t", mark(U32.is_eq(i, root))])

def slot.go(n: Nat, +ar: O.Arena, +i: U32, +root: U32) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+q:
      do IO<Unit>:
        IO.print(slot.line(root, i, ar))
        slot.go(q, ar, U32.add(i, 1), root)

def dump(+nm: String, r: R) -> IO(Unit):
  match r:
    case R{+ar, +i}:
      +hi = O.Arena.next(ar)
      do IO<Unit>:
        IO.print(String.concat(["# ", nm, " root=", U32.show(i), " next=", U32.show(hi), "\n"]))
        slot.go(U32.to_nat(hi), ar, 0, i)

def n1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e4m3(), True{}), pa)

def n2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v3", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e5m2(), True{}), pa)

def main() -> IO(Unit):
  +a1 = O.Arena.empty()
  +r1 = w1(a1)
  +a2 = O.Arena.empty()
  +r2 = n1(a2)
  +a3 = O.Arena.empty()
  +r3 = n2(a3)
  do IO<Unit>:
    dump("w1", r1)
    dump("n1", r2)
    dump("n2", r3)