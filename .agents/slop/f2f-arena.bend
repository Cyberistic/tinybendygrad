import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# f2f-arena.bend -- every SLOT of a fixture's arena, so a FORWARD edge -- a node whose
# src is a LATER slot -- can be NAMED rather than inferred from a `sig=` that is a
# toposort and cannot show one at all.
#
# ⚠ THE PARAM'S DTYPE IS `f2f_dt[fr]`, NOT `fr`, and this probe's first version had `fr`.
# Both real call sites pass a uint (dtype.py:142 `val.bitcast(f2f_dt[to])`, dtype.py:196
# `x.bitcast(f2f_dt[ctx[0]])`), `f2f_dt[f] = getattr(dtypes, f"uint{f.bitsize}")`
# (dtype.py:97), and `f2f.udt` IS that table -- which is why `dtype.bend`'s own gate
# passes `f2f.udt(fr)` here and the two lanes disagreed by 11 rows (`w1n` 33 against
# `q1n` 22). A probe whose fixture differs from the gate's measures a graph dtype.py
# never builds. `dd_par`'s dtype is its THIRD argument and it is what `mixin/dtype.py:53`
# reads, so the fold that removes the BITCAST is decided HERE.
#
# THE SLOT OFFSET IS 1, NOT 0. `ops.bend`'s `Arena` carries a bottom slot: slot 0 reads
# back `NOOP/0`, which is why a wrong index answers a plausible value instead of failing.
# CPython's `ORDER` has no bottom, so CPython slot `i` is port slot `i + 1` and the
# differ shifts rather than pretending the two numberings agree. Printing the offset in
# the header is the honest form.
#
# THE PRINT IS THE POINT. A wrong answer that is an arena INDEX is stable, so it would
# pass every fixture the file owns forever; only the SLOTS say which node a src points at.

type R is Data:
  R{ar: O.Arena, i: U32}

def miss(r: Maybe<&2, O.Found>, +ar: O.Arena) -> R:
  match r:
    case Some{+f}: R{O.Found.ar(f), O.Found.i(f)}
    case None{}: R{ar, 0}

# ONE FIXTURE, and `D.f2f.udt(fr)` is the receiver's dtype. `dd_par` interns the PARAM
# into `ar` and returns it grown, so `pa` is the arena the fixture STARTS from and the
# answer's arena is whatever `f2f` grew it into -- the two are not the same and `miss`
# reports the ANSWER's, which is the only arena a cone can be walked in.
def one(nm: String, +fr: S.Dt, +to: S.Dt, +ar: O.Arena) -> R:
  +p = D.dd_par(ar, nm, D.f2f.udt(fr))
  +pa = O.Found.ar(p)
  miss(D.f2f(pa, O.Found.i(p), fr, to, True{}), pa)

def q1(+ar: O.Arena) -> R: one("q1", S.fp8e4m3(), S.single(), ar)
def q2(+ar: O.Arena) -> R: one("q2", S.single(), S.fp8e4m3(), ar)
def q3(+ar: O.Arena) -> R: one("q3", S.single(), S.fp8e5m2(), ar)
def q4(+ar: O.Arena) -> R: one("q4", S.fp8e4m3fnuz(), S.single(), ar)
def q5(+ar: O.Arena) -> R: one("q5", S.single(), S.fp8e5m2fnuz(), ar)
def q7(+ar: O.Arena) -> R: one("q7", S.single(), S.double(), ar)

def mark(b: Bool) -> String:
  match b:
    case True{}: "ROOT"
    case False{}: ""

def fwd(b: Bool) -> String:
  match b:
    case True{}: "FORWARD"
    case False{}: ""

# THE TEST, and its first version was INVERTED. `fwd(Bool.or(is_lt(src, i), ...))` fires on
# almost every row, because `src < i` is TRUE for every well-formed edge -- `U32.is_lt(3, 5)`
# is `T` (`.agents/slop/ilt.bend`, measured). A flag that fires everywhere measures nothing
# and reads as a clean bill of health. The impossible edge is the other one: `i <= src`, so
# `not (src < i)` = `is_lt(i, src) or is_eq(i, src)`. A SELF-edge counts: the arena's
# bottom is at slot 0 with src 0, and `Arena.src` answers 0 for a short tuple, so a real
# self-reference and a missing src1 are the same index -- which is why the SELF case is
# excluded by `i != 0`.
#
# MEASURED, `.agents/slop/f2f-calibrate.py` direction 1, the inverted predicate rebuilt
# with the two arguments swapped and NOTHING ELSE changed, on the SAME fixed file and the
# SAME harness: 257 of 263 rows flagged. NOT 263 -- the six rows it misses are the six
# fixture bottoms (`q1 q2 q3 q4 q5 q7` slot 0), and it misses them because of the very
# `i != 0` exclusion the correct predicate needs. So the claim "fires on every row
# including `0 NOOP <- 0,0`" was WRONG IN ITS DETAIL: it fires on every row that is not a
# fixture bottom, and the bottom is silent for a reason that is not the inversion. The
# inversion is still the defect -- 257 flagged rows against CPython's 0 is a page of noise
# dressed as a report -- and the correction is stated because a calibration number that is
# quoted from memory is the thing this file exists to stop.
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

# ⚠ src2 IS PRINTED. The first version printed src0 and src1 only, so every `WHERE/3` came
# out with TWO srcs against CPython's three and the differ reported a WIRE disagreement
# on the last two rows of `q1` after `q1` had become byte-identical otherwise -- a probe
# limitation that read as a port bug. `Arena.src` answers the arena BOTTOM for an index
# past the end, so a `CONST/0` prints `0,0,0` and the differ truncates to `op/N`.
def fwd3(+i: U32, +ar: O.Arena) -> Bool:
  Bool.or(fwd1(i, O.Arena.src0(ar, i)),
    Bool.or(fwd1(i, O.Arena.src(ar, i, 1)), fwd1(i, O.Arena.src(ar, i, 2))))

def slot.line(+root: U32, +i: U32, +ar: O.Arena) -> String:
  String.concat([U32.show(i), "\t", D.dd_sig1(ar, i), "\t", D.dd_lab(ar, i),
                 "\t<- ", U32.show(O.Arena.src0(ar, i)), ",", U32.show(O.Arena.src(ar, i, 1)),
                 ",", U32.show(O.Arena.src(ar, i, 2)),
                 "\t", fwd(fwd3(i, ar)),
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
  +r1 = q1(a1)
  +a2 = O.Arena.empty()
  +r2 = q2(a2)
  +a3 = O.Arena.empty()
  +r3 = q3(a3)
  +a4 = O.Arena.empty()
  +r4 = q4(a4)
  +a5 = O.Arena.empty()
  +r5 = q5(a5)
  +a7 = O.Arena.empty()
  +r7 = q7(a7)
  do IO<Unit>:
    dump("q1", r1)
    dump("q2", r2)
    dump("q3", r3)
    dump("q4", r4)
    dump("q5", r5)
    dump("q7", r7)
