# gates/divandmod-gate.bend -- the gate driver for `tinybendygrad/uop/divandmod.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/uop/divandmod.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("nrules", P.t_nrules())
    b : Unit <- row("rej0", P.dm_rejlen(0))
    c : Unit <- row("rej1", P.dm_rejlen(1))
    d : Unit <- row("rej2", P.dm_rejlen(2))
    e : Unit <- row("nroots", P.t_nroots())
    # the ZERO DIVISOR, which Python raises on
    f : Unit <- row("zero_r04", P.t_zero(4))
    g0 : Unit <- row("zero_r11", P.t_zero(11))
    h : Unit <- row("zero_r23", P.t_zero(23))
    i : Unit <- row("zero_r05", P.t_zero(5))
    j : Unit <- row("zero_r15", P.t_zero(15))
    # the twenty-five roots: did a rule fire, and to what
    k : Unit <- row("on_r00", P.t_on(P.trees(), 0))
    l : Unit <- rows("out_r00", P.t_out(P.trees(), 0))
    m : Unit <- row("on_r01", P.t_on(P.trees(), 1))
    n : Unit <- rows("out_r01", P.t_out(P.trees(), 1))
    o : Unit <- row("on_r02", P.t_on(P.trees(), 2))
    p : Unit <- rows("out_r02", P.t_out(P.trees(), 2))
    q : Unit <- row("grown_r02", P.t_grown(P.trees(), 2))
    r : Unit <- row("on_r03", P.t_on(P.trees(), 3))
    s : Unit <- rows("out_r03", P.t_out(P.trees(), 3))
    t : Unit <- row("on_r04", P.t_on(P.trees(), 4))
    u : Unit <- row("on_r05", P.t_on(P.trees(), 5))
    v : Unit <- rows("out_r05", P.t_out(P.trees(), 5))
    w : Unit <- row("on_r06", P.t_on(P.trees(), 6))
    x : Unit <- rows("out_r06", P.t_out(P.trees(), 6))
    y : Unit <- row("on_r07", P.t_on(P.trees(), 7))
    z : Unit <- rows("out_r07", P.t_out(P.trees(), 7))
    a1 : Unit <- row("on_r08", P.t_on(P.trees(), 8))
    b1 : Unit <- rows("out_r08", P.t_out(P.trees(), 8))
    c1 : Unit <- row("on_r09", P.t_on(P.trees(), 9))
    d1 : Unit <- rows("out_r09", P.t_out(P.trees(), 9))
    e1 : Unit <- row("on_r10", P.t_on(P.trees(), 10))
    f1 : Unit <- rows("out_r10", P.t_out(P.trees(), 10))
    g1 : Unit <- row("on_r11", P.t_on(P.trees(), 11))
    h1 : Unit <- row("on_r12", P.t_on(P.trees(), 12))
    i1 : Unit <- rows("out_r12", P.t_out(P.trees(), 12))
    j1 : Unit <- row("on_r13", P.t_on(P.trees(), 13))
    k1 : Unit <- rows("out_r13", P.t_out(P.trees(), 13))
    l1 : Unit <- rows("out_r14", P.t_out(P.trees(), 14))
    m1 : Unit <- rows("out_r15", P.t_out(P.trees(), 15))
    n1 : Unit <- rows("out_r16", P.t_out(P.trees(), 16))
    o1 : Unit <- rows("out_r17", P.t_out(P.trees(), 17))
    p1 : Unit <- rows("out_r18", P.t_out(P.trees(), 18))
    q1 : Unit <- rows("out_r19", P.t_out(P.trees(), 19))
    r1 : Unit <- rows("out_r20", P.t_out(P.trees(), 20))
    s1 : Unit <- rows("out_r21", P.t_out(P.trees(), 21))
    t1 : Unit <- row("on_r22", P.t_on(P.trees(), 22))
    u1 : Unit <- row("on_r23", P.t_on(P.trees(), 23))
    v1 : Unit <- row("on_r24", P.t_on(P.trees(), 24))
    # the growth counts that pin each rule's SHAPE as well as its answer
    w1 : Unit <- row("grown_r00", P.t_grown(P.trees(), 0))
    x1 : Unit <- row("grown_r05", P.t_grown(P.trees(), 5))
    y1 : Unit <- row("grown_r06", P.t_grown(P.trees(), 6))
    row("grown_r01", P.t_grown(P.trees(), 1))
    row("zero_r25", P.t_zero(25))
    row("on_r25", P.t_on(P.trees(), 25))
    rows("out_r25", P.t_out(P.trees(), 25))

# the fuzz driver. no argument is the gate above, unchanged; one argument is a case
# FILE, and the case is ONE LINE `op|a|b` -- a CONST/CONST tree built the same way
# the gate's `r13`..`r16` fixtures build theirs. The dispatch is on the SHAPE of
# the argument list, so a missing case file cannot be mistaken for a case.
#
# THE CANONICAL LINE IS THE FOLD'S DENOTATION, not its tree: a tree-shaped line
# would compare Python's SUB canonicalisation against this file's (divergence B)
# on every case. The denotation is the same integer on both sides. `nofold` is
# Python's `None`; `RAISED` is its `ZeroDivisionError` at divandmod.py:11, which
# this file reports as the Bool `P.dm_zero`.

# `op` -- the five ops the case format spells. TRUNCDIV/TRUNCMOD/FDIV are REAL Ops that
# the table does NOT claim, so a case naming one must print `nofold` on both
# sides: the row that says the table's op set is {DIV, MOD} and not
# something wider. `case _` answers DIV, the only default that cannot make a
# typo'd case name a DIFFERENT op.
def dmc.op(s: String) -> O.Op:
  match s:
    case "DIV": O.OpsDIV{}
    case "MOD": O.OpsMOD{}
    case "TRUNCDIV": O.OpsTRUNCDIV{}
    case "TRUNCMOD": O.OpsTRUNCMOD{}
    case "FDIV": O.OpsFDIV{}
    case _: O.OpsDIV{}

# a signed decimal literal as a `U32` bit pattern. `a` and `b` are int32 in
# both languages and this file has no signed type, so the case's decimal is read
# as a magnitude and NEGATED here -- `H.i32_neg` is `U32.sub(0, x)`, which is
# the two's complement Python writes. A leading `-` is the only sign, which is
# all the generator emits.
def dmc.num.chars(cs: List<&2, Char>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case c <> t: dmc.num.chars(t, U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(c), 48)))

def dmc.num.of(s: String) -> U32:
  dmc.num.chars(String.to_list(s), 0)

def dmc.num.put(neg: Bool, v: U32) -> U32:
  match neg:
    case True{}: H.i32_neg(v)
    case False{}: v

def dmc.num.go(neg: Bool, s: String) -> U32:
  match neg:
    case True{}: dmc.num.put(True{}, dmc.num.of(String.drop(s, 1n)))
    case False{}: dmc.num.of(s)

def dmc.num(+s: String) -> U32:
  dmc.num.go(String.starts_with(s, "-"), s)

def dmc.nth(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "0"

def dmc.field(fs: List<&2, String>, k: U32) -> String:
  dmc.nth(List.get(&2, String, fs, U32.to_nat(k)))

# THE ARENA: two CONSTs and the op node, in binding order, exactly the shape
# `P.trees()` builds for `r13`..`r16`.
def dmc.arena(op: O.Op, a: U32, b: U32) -> O.Found:
  +ar = O.Arena.empty()
  +ca = O.UOp.const(ar, O.CInt{H.i64_of_i32(a)})
  +cb = O.UOp.const(O.Found.ar(ca), O.CInt{H.i64_of_i32(b)})
  O.UOp.alu(O.Found.ar(cb), op, [O.Found.i(ca), O.Found.i(cb)])

# THE DENOTATION of a folded node, read off the tree the port ANSWERED with. A
# CONST is its own value; the `SUB(x, MUL(q, y))` `P.dm_point.sub` builds is `x - q*y`,
# and `q` is READ from the port's own interned node, never re-derived here.
#
# the arithmetic is 32-bit and python's is not, and that is the point: tinygrad
# CONSTs are mathematical Python ints, so `1 % -2147483648` is 1 while this
# file's `MUL(-1, INT_MIN)` is already 2^31 before the SUB. Both P.trees denote the
# same integer, and the oracle evaluates the tree in Python's unbounded ints so
# this line compares denotations and not arithmetic widths.
def dmc.den.const(ar: O.Arena, i: U32) -> U32:
  P.dm_ival(P.dm_val(ar, i))

def dmc.den.mul(+ar: O.Arena, +m: U32) -> U32:
  U32.mul(dmc.den.const(ar, O.Arena.src0(ar, m)), dmc.den.const(ar, O.Arena.src(ar, m, 1)))

def dmc.den.sub(+ar: O.Arena, +d: U32) -> U32:
  U32.sub(dmc.den.const(ar, O.Arena.src0(ar, d)), dmc.den.mul(ar, O.Arena.src(ar, d, 1)))

def dmc.den.go(op: O.Op, ar: O.Arena, i: U32) -> U32:
  match op:
    case O.OpsCONST{}: dmc.den.const(ar, i)
    case O.OpsSUB{}: dmc.den.sub(ar, i)
    case _: 0

def dmc.den(+ar: O.Arena, +i: U32) -> U32:
  dmc.den.go(O.Arena.op(ar, i), ar, i)

# THE TWO CANONICAL ANSWERS, plus the one Python REFUSES. `CONST n` is a folded
# value and `nofold` is its `None`. `RAISED` is its `ZeroDivisionError`, and this
# file has no `raise`: it reports the condition as the Bool `P.dm_zero`, so `RAISED`
# is a distinct word and not a synonym for `nofold`.
def dmc.out.hit.go(on: U32, v: U32) -> String:
  match on:
    case 0: "nofold"
    case _: String.concat(["CONST ", P.dm_show(v)])

def dmc.out.hit(+h: P.Hit) -> String:
  dmc.out.hit.go(P.Hit.on(h), dmc.den(P.Hit.ar(h), P.Hit.i(h)))

def dmc.out(zero: Bool, +h: P.Hit) -> String:
  match zero:
    case True{}: "RAISED"
    case _: dmc.out.hit(h)

# The zero test is reported ONLY where Python reaches `P.fold_divmod_general` at all,
# which is where RULE 2 claims the node -- a TRUNCMOD root is claimed by nobody, so
# Python answers `None` there and never raises. The op set is READ from
# `P.dm_table()` rather than spelled here, so a wider rule 2 moves the word with it.
def dmc.two.go(m: Maybe<&2, O.PMEntry>) -> List<&2, O.Op>:
  match m:
    case Some{e}: O.PMEntry.ops(e)
    case None{}: Nil{}

def dmc.two() -> List<&2, O.Op>:
  dmc.two.go(List.get(&2, O.PMEntry, O.PMEntrys.es(P.dm_table()), 2n))

def dmc.of.put.go(zero: Bool, +h: P.Hit) -> String:
  dmc.out(zero, h)

def dmc.of.put.reach(+f: O.Found) -> Bool:
  O.pm_claimed(dmc.two(), O.Found.ar(f), O.Found.i(f))

# the case: `op|a|b`, one line. The zero test is on the ROOT, which is the index
# the scan was given, and it runs on the arena the scan ran on.
def dmc.of.put(+f: O.Found) -> String:
  dmc.of.put.go(Bool.and(dmc.of.put.reach(f), P.dm_zero(O.Found.ar(f), O.Found.i(f))),
                P.div_and_mod_symbolic(F.folded(O.Found.ar(f)), O.Found.i(f)))

def dmc.of(+fs: List<&2, String>) -> String:
  dmc.of.put(dmc.arena(dmc.op(dmc.field(fs, 0)),
                       dmc.num(dmc.field(fs, 1)),
                       dmc.num(dmc.field(fs, 2))))

def dmc.run(p: String) -> IO(Unit):
  do IO<Unit>:
    s : String <- H.printable(p, 1)
    IO.print(dmc.of(String.split(s, '|')))

def dispatch(ps: List<&1, String>) -> IO(Unit):
  match ps:
    case Nil{}: gate()
    case p <> _: dmc.run(p)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    u : Unit <- dispatch(List.tail(&1, String, as))
    IO.pure(Unit, u)
