import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# dd-cdivprobe.bend -- the CDIV/CMOD CONE, position by position, with labels.
#
# dd-gap.py diffs two `sig` rows as `op/nsrc` MULTISETS, which names a missing node's OP
# but not WHICH node: a `CMPLT` in a 2431-node cone is 2431 candidates. This prints
# `position  op/nsrc  label  <- src0,src1` for the cone of one fixture, and
# `.agents/slop/dd-cone-py.py` prints the same for CPython's, so the two can be read
# side by side at one position. It calls the port's own `l2i` on the gate's own fixture
# (WPOOL[u32][0..3]) and does not edit dtype.bend.
#
# FOUR BEND SHAPES, all MEASURED HERE by writing the wrong one first:
#   1. `match` on a computed value is refused -> the Bool is a PARAMETER.
#   2. `match` on a def parameter NESTED inside another match's arm is refused -> the
#      Bool gets a LEAF def whose first statement is the match (`dd_join.ck`).
#   3. The two cannot be mutually recursive -> the helper is a leaf and the WALKER
#      recurses (`dd_eck`).
#   4. `match` on a `let`-bound name is refused -> `l2i`'s answer is a def PARAMETER.
# Plus: an `IO` block sequences with `do IO<Unit>:`, `IO.noop` does not exist (`IO.print("")`
# does), and a 50KB accumulated `String` reads as an EMPTY row with no error.

def lab(+ar: O.Arena, +u: U32) -> String: D.dd_lab(ar, u)

def inrange(+i: U32, lo: U32, hi: U32) -> Bool:
  Bool.and(U32.is_ge(i, lo), U32.is_le(i, hi))

def cone.line(k: Bool, +ar: O.Arena, +u: U32, +i: U32) -> String:
  match k:
    case True{}:
      String.concat([U32.show(i), "\t", D.dd_sig1(ar, u), "\t", lab(ar, u), "\t<- ",
                     lab(ar, O.Arena.src0(ar, u)), ",", lab(ar, O.Arena.src(ar, u, 1)), "\n"])
    case False{}: ""

# EVERY SLOT in the window, `index=OP/nsrc\tlabel\t<- srcs`, which is the SAME fact
# `.agents/slop/dd-cdiv-py.py` dumps for CPython, so the two arenas compare position by
# position. NOT a CONST filter: the first version of this probe filtered on `D.dd_ck`
# and printed CAST and MUL slots as if they were constants, which is what a wrong
# reading of the arena looks like.
def slot.go(n: Nat, +ar: O.Arena, +i: U32, +lo: U32, +hi: U32) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+q:
      do IO<Unit>:
        IO.print(cone.line(inrange(U32.add(i, 1), lo, hi), ar, U32.add(i, 1), U32.add(i, 1)))
        slot.go(q, ar, U32.add(i, 1), lo, hi)

def cone.go(n: Nat, +ar: O.Arena, xs: List<&2, U32>, +i: U32, +lo: U32, +hi: U32) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+q:
      match xs:
        case Nil{}: IO.print("")
        case +u <> t:
          do IO<Unit>:
            IO.print(cone.line(inrange(i, lo, hi), ar, u, i))
            cone.go(q, ar, t, U32.add(i, 1), lo, hi)

def report(+nm: String, r: Maybe<&2, D.W2>, +from: U32, +lo: U32, +hi: U32, slots: Bool) -> IO(Unit):
  match r:
    case Some{+w}:
      +war = D.W2.ar(w)
      +to = O.Arena.next(war)
      +c = D.dd_cone(D.dd_fuel(war), war, [D.W2.lo(w), D.W2.hi(w)])
      do IO<Unit>:
        IO.print(String.concat(["# ", nm, " from=", U32.show(from), " to=", U32.show(to),
                                " n=", U32.show(U32.sub(to, from)),
                                " lo=", U32.show(D.W2.lo(w)), " hi=", U32.show(D.W2.hi(w)),
                                " cone=", U32.show(U32.from_nat(List.length(&2, U32, c))), "\n"]))
        slot.go(U32.to_nat(U32.sub(to, from)), war, from, lo, hi)
        cone.go(U32.to_nat(U32.sub(to, from)), war, c, 0, lo, hi)
        IO.print(String.concat(["# ", nm, " lo-tree: ", D.dd_tree(war, D.W2.lo(w)), "\n"]))
    case None{}: IO.print(String.concat([nm, " REFUSED\n"]))

def main() -> IO(Unit):
  +nd = D.dd_wpool.step(24n, O.Arena.empty(), Nil{}, 0, 0)
  +ps = D.Nd.ns(nd)
  +ar = D.Nd.ar(nd)
  +from = O.Arena.next(ar)
  +lo: U32 = 25
  +hi: U32 = 50
  do IO<Unit>:
    g3 : Maybe<&2, D.W2> = D.l2i(ar, O.OpsCDIV{}, S.int32(), S.uint32(), [D.nth(ps, 9n), D.nth(ps, 10n), D.nth(ps, 11n), D.nth(ps, 12n)])
    report("lgq", g3, from, lo, hi, True{})
    g1 : Maybe<&2, D.W2> = D.l2i(ar, O.OpsCDIV{}, S.uint32(), S.uint32(), [D.nth(ps, 9n), D.nth(ps, 10n), D.nth(ps, 11n), D.nth(ps, 12n)])
    report("lgs", g1, from, lo, hi, False{})