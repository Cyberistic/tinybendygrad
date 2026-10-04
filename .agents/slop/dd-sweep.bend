import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# dd-sweep.bend -- THE SIZE SWEEP. The `l2i_cdiv.abs` precedent: an arena-aliasing
# defect in this file AGREED at one node-count configuration and broke at the next, so a
# fix is not evidence until it has held at several arena sizes.
#
# IT PREPENDS `k` DUMMY PARAMs TO THE ARENA AND THEN RUNS THE GATE'S OWN ROW SEQUENCE
# (rows 0..27 of `l2i.pick`) ON ONE THREADED ARENA, printing the four ROWS THAT HAVE
# ALREADY FAILED ONCE -- the CDIV/CMOD constant lists and cone sizes -- plus `lg5k`. If a
# fix is reading an INDEX where upstream reads a VALUE it will move with `k`; the
# constant lists are the rows that catch it, because `lgqk`'s first constant is `C(i)` for
# `i = 63` and the defect it replaced put the arena INDEX of `C(1)` there.
#
# `k` COMES FROM `IO.args` because a sweep needs more than one configuration per RUN and
# bend has no globals to bump; the caller loops. Measured on this tree: `k = 0, 1, 2, 5,
# 17, 64` all print byte-identical `lgqk/lgrk/lgsk/lgtk/lg5k` and identical cone sizes.

# `PADN` IS A LITERAL AND NOT `IO.args`: `IO.args` is an effect VALUE, not a `List`, and
# `IO.try(List<&2, String>, IO.args)` is refused with "expected : ... -> IO.OP<R>", so
# reading argv needs a shape I did not find in `bend guide`. The caller substitutes the
# literal instead, which is also the only way a sweep can be READ: one line of diff per
# configuration.
def pad.go(n: Nat, +ar: O.Arena, +k: U32) -> O.Arena:
  match n:
    case 0n: ar
    case 1n+q: pad.go(q, D.dd_par(ar, "pad", S.uint32()), k)

def pad(k: U32, +ar: O.Arena) -> O.Arena: pad.go(U32.to_nat(k), ar, k)

def ar.of(r: Maybe<&2, D.W2>, dflt: O.Arena) -> O.Arena:
  match r:
    case Some{+w}: D.W2.ar(w)
    case None{}: dflt

# THE FOUR SENSITIVE ROWS, AS `(name, sig-length, k=)` STRINGS.
def row1(+nm: String, r: Maybe<&2, D.W2>, +from: U32) -> String:
  match r:
    case Some{+w}:
      +war = D.W2.ar(w)
      +to = O.Arena.next(war)
      +c = D.dd_cone(D.dd_fuel(war), war, [D.W2.lo(w), D.W2.hi(w)])
      String.concat([nm, "cone=", U32.show(U32.from_nat(List.length(&2, U32, c))), " k=",
                     D.dd_eck(war, D.dd_fuel(war), c, True{}, ""), "\n"])
    case None{}: String.concat([nm, "REFUSED\n"])

def main() -> IO(Unit):
  +nd = D.dd_wpool.step(24n, pad(1, O.Arena.empty()), Nil{}, 0, 0)
  +ps = D.Nd.ns(nd)
  +a0 = D.Nd.ar(nd)
  +u9 = D.ws2(D.nth(ps, 9n), D.nth(ps, 10n))
  +u9b = D.ws2(D.nth(ps, 4n), D.nth(ps, 5n))
  +u9c = D.ws2(D.nth(ps, 14n), D.nth(ps, 15n))
  +u9d = D.ws2(D.nth(ps, 19n), D.nth(ps, 20n))
  +u3 = D.ws4(D.nth(ps, 9n), D.nth(ps, 10n), D.nth(ps, 11n), 0)
  +u4 = D.ws4(D.nth(ps, 9n), D.nth(ps, 10n), D.nth(ps, 11n), D.nth(ps, 12n))
  +u5 = D.ws5(D.nth(ps, 9n), D.nth(ps, 10n), D.nth(ps, 11n), D.nth(ps, 12n), D.nth(ps, 13n))
  +g0 = D.l2i(a0, O.OpsNEG{}, S.int32(), S.uint32(), u9)
  +a1 = ar.of(g0, a0)
  +g1 = D.l2i(a1, O.OpsCAST{}, S.int64(), S.int32(), u9b)
  +a2 = ar.of(g1, a1)
  +g2 = D.l2i(a2, O.OpsCAST{}, S.int64(), S.uint32(), u9)
  +a3 = ar.of(g2, a2)
  +g3 = D.l2i(a3, O.OpsCAST{}, S.int64(), S.boolean(), u9c)
  +a4 = ar.of(g3, a3)
  +g4 = D.l2i(a4, O.OpsCAST{}, S.int64(), S.single(), u9d)
  +a5 = ar.of(g4, a4)
  +g5 = D.l2i(a5, O.OpsCAST{}, S.uint64(), S.int32(), u9b)
  +a6 = ar.of(g5, a5)
  +g6 = D.l2i(a6, O.OpsCAST{}, S.int32(), S.uint32(), u9)
  +a7 = ar.of(g6, a6)
  +g7 = D.l2i(a7, O.OpsBITCAST{}, S.int64(), S.uint32(), u9)
  +a8 = ar.of(g7, a7)
  +g8 = D.l2i(a8, O.OpsSHL{}, S.int32(), S.uint32(), u3)
  +a9 = ar.of(g8, a8)
  +g9 = D.l2i(a9, O.OpsSHR{}, S.int32(), S.uint32(), u3)
  +a10 = ar.of(g9, a9)
  +g10 = D.l2i(a10, O.OpsSHR{}, S.uint32(), S.uint32(), u3)
  +a11 = ar.of(g10, a10)
  +g11 = D.l2i(a11, O.OpsADD{}, S.int32(), S.uint32(), u4)
  +a12 = ar.of(g11, a11)
  +g12 = D.l2i(a12, O.OpsSUB{}, S.int32(), S.uint32(), u4)
  +a13 = ar.of(g12, a12)
  +g13 = D.l2i(a13, O.OpsMUL{}, S.int32(), S.uint32(), u4)
  +a14 = ar.of(g13, a13)
  +g14 = D.l2i(a14, O.OpsCMPLT{}, S.int32(), S.uint32(), u4)
  +a15 = ar.of(g14, a14)
  +g15 = D.l2i(a15, O.OpsCMPEQ{}, S.int32(), S.uint32(), u4)
  +a16 = ar.of(g15, a15)
  +g16 = D.l2i(a16, O.OpsCMPNE{}, S.int32(), S.uint32(), u4)
  +a17 = ar.of(g16, a16)
  +g17 = D.l2i(a17, O.OpsXOR{}, S.int32(), S.uint32(), u4)
  +a18 = ar.of(g17, a17)
  +g18 = D.l2i(a18, O.OpsOR{}, S.int32(), S.uint32(), u4)
  +a19 = ar.of(g18, a18)
  +g19 = D.l2i(a19, O.OpsAND{}, S.int32(), S.uint32(), u4)
  +a20 = ar.of(g19, a19)
  +g20 = D.l2i(a20, O.OpsWHERE{}, S.int32(), S.uint32(), u5)
  +a21 = ar.of(g20, a20)
  +g21 = D.l2i(a21, O.OpsMAX{}, S.int32(), S.uint32(), u4)
  +a22 = ar.of(g21, a21)
  +g22 = D.l2i(a22, O.OpsFLOORDIV{}, S.int32(), S.uint32(), u4)
  +a23 = ar.of(g22, a22)
  +g23 = D.l2i(a23, O.OpsCDIV{}, S.int32(), S.uint32(), u4)
  +a24 = ar.of(g23, a23)
  +g24 = D.l2i(a24, O.OpsCMOD{}, S.int32(), S.uint32(), u4)
  +a25 = ar.of(g24, a24)
  +g25 = D.l2i(a25, O.OpsCDIV{}, S.uint32(), S.uint32(), u4)
  +a26 = ar.of(g25, a25)
  +g26 = D.l2i(a26, O.OpsCMOD{}, S.uint32(), S.uint32(), u4)
  +f4 = O.Arena.next(a5)
  +f23 = O.Arena.next(a23)
  +f25 = O.Arena.next(a25)
  +f26 = O.Arena.next(a26)
  do IO<Unit>:
    IO.print(String.concat(["# pad=", U32.show(1), "\n"]))
    IO.print(row1("lgq", g23, f23))
    IO.print(row1("lgr", g24, f23))
    IO.print(row1("lgs", g25, f25))
    IO.print(row1("lgt", g26, f26))