import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/helpers.bend as H

# dd-bandpad.bend -- `f2f` with `pad` PARAMs minted BEFORE the fixture's own.
#
# THIS IS THE FIXTURE THE SEVEN MASK SITES NEED, AND IT IS THE ONLY ONE THAT CAN FAIL.
#
# A wrong mask that is an ARENA INDEX is a function of the fixture's POSITION, not of its
# value: `dd_band`'s third parameter is `dc_cint(ar, k)`, so passing `O.Found.i(s)` interns
# `CONST <the slot number of s>`. Nothing about `v` changes that, so the gate's fixtures --
# which all start at slot 0 or slot 1 -- cannot separate it. PREPENDING PARAMs moves every
# index by exactly `pad`, so the wrong mask changes by exactly `pad` while the right mask
# does not move at all.
#
# The measured signature, on the UNFIXED tree, `.agents/slop/dd-bandpad.txt`:
#
#   pad   w1n   n1 mask CONST the port interned   CPython's mask
#     0    26        C(2)   at L1578 f2f.sign      C(128)
#     1    27        C(3)                          C(128)
#     2    28        C(4)                          C(128)
#     5    31        C(7)                          C(128)
#    17    43       C(19)                          C(128)
#    64    90       C(66)                          C(128)
#
# and at pad=128 the wrong mask `C(130)` is no longer a submask of anything and the answer
# stops depending on `v` at all: `f2f` becomes a CONSTANT function of its input's POSITION.
# A defect whose wrong answer is a CONSTANT is the worst kind, because it is stable: it
# would pass every fixture the file happens to own, forever.
#
# BEND SHAPES: a `match` cannot scrutinise a computed value, so the `Maybe` answer arrives as
# a def PARAMETER; `+nm`, `+i` and `+f` are LINEARITY, each measured by writing it wrong.

type R is Data:
  R{ar: O.Arena, i: U32}

def pad.go(n: Nat, +ar: O.Arena, +nm: String) -> O.Arena:
  match n:
    case 0n: ar
    case 1n+q:
      +f = D.dd_par(ar, nm, S.uint32())
      pad.go(q, O.Found.ar(f), nm)

def pad(n: Nat, ar: O.Arena) -> O.Arena: pad.go(n, ar, "pad")

def miss(r: Maybe<&2, O.Found>, +ar: O.Arena) -> R:
  match r:
    case Some{+f}: R{O.Found.ar(f), O.Found.i(f)}
    case None{}: R{ar, U32.sub(O.Arena.next(ar), 1)}

def w1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v1", S.fp8e4m3())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.fp8e4m3(), S.single(), True{}), pa)

def n1(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v2", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e4m3(), True{}), pa)

def n2(+ar: O.Arena) -> R:
  +p = D.dd_par(ar, "v3", S.single())
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), S.single(), S.fp8e5m2(), True{}), pa)

def one(+nm: String, r: R) -> IO(Unit):
  match r:
    case R{+ar, +i}:
      +fu = D.dd_fuel(ar)
      +cn = D.dd_cone(fu, ar, [i])
      do IO<Unit>:
        IO.print(String.concat([nm, "=", D.dd_tree(ar, i), "\n"]))
        IO.print(String.concat([nm, "n=", U32.show(O.Arena.next(ar)), "\n"]))
        IO.print(String.concat([nm, "k=", D.dd_eck(ar, fu, cn, True{}, ""), "\n"]))

# ONE CALL PER `pad`, because an arena is linear and each `f2f` needs its own.
def wp0(+ar: O.Arena) -> R: w1(pad(0n, ar))
def wp1(+ar: O.Arena) -> R: w1(pad(1n, ar))
def wp2(+ar: O.Arena) -> R: w1(pad(2n, ar))
def wp5(+ar: O.Arena) -> R: w1(pad(5n, ar))
def wp17(+ar: O.Arena) -> R: w1(pad(17n, ar))
def wp64(+ar: O.Arena) -> R: w1(pad(64n, ar))
def n1p0(+ar: O.Arena) -> R: n1(pad(0n, ar))
def n1p1(+ar: O.Arena) -> R: n1(pad(1n, ar))
def n1p2(+ar: O.Arena) -> R: n1(pad(2n, ar))
def n1p5(+ar: O.Arena) -> R: n1(pad(5n, ar))
def n1p17(+ar: O.Arena) -> R: n1(pad(17n, ar))
def n1p64(+ar: O.Arena) -> R: n1(pad(64n, ar))
def n2p0(+ar: O.Arena) -> R: n2(pad(0n, ar))
def n2p1(+ar: O.Arena) -> R: n2(pad(1n, ar))
def n2p2(+ar: O.Arena) -> R: n2(pad(2n, ar))
def n2p5(+ar: O.Arena) -> R: n2(pad(5n, ar))
def n2p17(+ar: O.Arena) -> R: n2(pad(17n, ar))
def n2p64(+ar: O.Arena) -> R: n2(pad(64n, ar))

def main() -> IO(Unit):
  +a0 = O.Arena.empty()
  +r0 = nwp0(a0)
  +a1 = O.Arena.empty()
  +r1 = nwp1(a1)
  +a2 = O.Arena.empty()
  +r2 = nwp2(a2)
  +a5 = O.Arena.empty()
  +r5 = nwp5(a5)
  +a17 = O.Arena.empty()
  +r17 = p17(a17)
  +a64 = O.Arena.empty()
  +r64 = p64(a64)
  +b0 = O.Arena.empty()
  +s0 = nn1p0(b0)
  +b1 = O.Arena.empty()
  +s1 = nn1p1(b1)
  +b2 = O.Arena.empty()
  +s2 = nn1p2(b2)
  +b5 = O.Arena.empty()
  +s5 = nn1p5(b5)
  +b17 = O.Arena.empty()
  +s17 = q17(b17)
  +b64 = O.Arena.empty()
  +s64 = q64(b64)
  +c0 = O.Arena.empty()
  +t0 = nn2p0(c0)
  +c1 = O.Arena.empty()
  +t1 = nn2p1(c1)
  +c2 = O.Arena.empty()
  +t2 = nn2p2(c2)
  +c5 = O.Arena.empty()
  +t5 = nn2p5(c5)
  +c17 = O.Arena.empty()
  +t17 = r17(c17)
  +c64 = O.Arena.empty()
  +t64 = r64(c64)
  do IO<Unit>:
    one("w1.p0", g0)
    one("w1.p1", g1)
    one("w1.p2", g2)
    one("w1.p5", g5)
    one("w1.p17", g17)
    one("w1.p64", g64)
    one("n1.p0", h0)
    one("n1.p1", h1)
    one("n1.p2", h2)
    one("n1.p5", h5)
    one("n1.p17", h17)
    one("n1.p64", h64)
    one("n2.p0", j0)
    one("n2.p1", j1)
    one("n2.p2", j2)
    one("n2.p5", j5)
    one("n2.p17", j17)
    one("n2.p64", j64)