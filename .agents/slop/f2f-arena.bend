import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# f2f-arena.bend -- every SLOT of the `f1` fixture's arena, the ONE fixture that reaches
# `f2f.fnuz`, so the `f2f.em1` collapse inside it can be NAMED rather than inferred.
#
# `dd-bandarena.bend` prints `w1`, and `w1` is fp8e4m3 -> float32, which is NOT fnuz, so
# it takes `f2f.up.tail`'s `f2f.ocp` arm. `f2f.em1` is called from THREE sites -- `f2f.qnan`
# (w1's), `f2f.fnuz` (f1's) and `f2f.down.npat` (n2's) -- and only the last two are
# separable now that `f2f.ocp` no longer calls it.
#
# THE PRINT IS THE POINT. A wrong answer that is an arena INDEX is stable, so it would
# pass every fixture the file owns forever; only the SLOTS say which node a src points at.

type R is Data:
  R{ar: O.Arena, i: U32}

def miss(r: Maybe<&2, O.Found>, +ar: O.Arena) -> R:
  match r:
    case Some{+f}: R{O.Found.ar(f), O.Found.i(f)}
    case None{}: R{ar, 0}

def f1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "f1", S.fp8e4m3fnuz())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.fp8e4m3fnuz(), S.single(), True{}), pa)

def n2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "n2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e5m2(), True{}), pa)

def mark(b: Bool) -> String:
  match b:
    case True{}: "ROOT"
    case False{}: ""

def fwd(b: Bool) -> String:
  match b:
    case True{}: "FORWARD"
    case False{}: ""

# THE TEST, and its first version was INVERTED. `fwd(Bool.or(is_lt(src, i), ...))` fires on
# every row, because `src < i` is TRUE for every well-formed edge -- `U32.is_lt(3, 5)` is
# `T` (`.agents/slop/ilt.bend`, measured). A flag that fires everywhere measures nothing and
# reads as a clean bill of health. The impossible edge is the other one: `i <= src`, so
# `not (src < i)` = `is_lt(i, src) or is_eq(i, src)`. A SELF-edge counts: the arena's
# bottom is at slot 0 with src 0, and `Arena.src` answers 0 for a short tuple, so a real
# self-reference and a missing src1 are the same index -- which is why the SELF case is
# excluded by `i != 0`.
# BOTH PARAMETERS ARE SPENT, and bend says so at each one in turn: `i` by `Bool.or`'s
# second argument, then `src` by the `is_eq`. The fix is a local REBIND per use, which is
# the same shape `arena-affine-probe.bend`'s `case Some{+ar, +i}` uses -- read a value once
# into a `+` binder and hand that to each consumer.
def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(j, src)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)

def slot.line(+root: U32, +i: U32, +ar: O.Arena) -> String:
  String.concat([U32.show(i), "\t", D.dd_sig1(ar, i), "\t", D.dd_lab(ar, i),
                 "\t<- ", U32.show(O.Arena.src0(ar, i)), ",", U32.show(O.Arena.src(ar, i, 1)),
                 "\t", fwd(Bool.or(fwd1(i, O.Arena.src0(ar, i)), fwd1(i, O.Arena.src(ar, i, 1)))),
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

def main() -> IO(Unit):
  +a1 = O.Arena.empty()
  +r1 = f1(a1)
  +a2 = O.Arena.empty()
  +r2 = n2(a2)
  do IO<Unit>:
    dump("f1", r1)
    dump("n2", r2)