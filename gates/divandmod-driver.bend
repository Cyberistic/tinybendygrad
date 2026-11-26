import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/divandmod.bend as P

# THE PORT SIDE OF `gates/divandmod-oracle.py`, AND IT READS THE SAME CASE
# FILE THE ORACLE READS.
#
# ONE FILE, TWO READERS: `gates/divandmod-cases.rows` holds the GRAPHS, this
# driver reads it and prints one answer per case, and
# `gates/divandmod-oracle.py` READS THE SAME FILE and builds the same graphs in
# CPython.  **So the port and the oracle cannot be measuring two different
# graphs**, which is the defect a hand-written pair of fixtures has by
# construction.
#
# AND THE CASE IS A FIXED SHAPE -- `name|op|k|c|n|d` -- AND NOT AN
# S-EXPRESSION, AND THE REASON IS MEASURED.  MEASURED 2026-11-24: THE FIRST
# DRAFT READ A S-EXPRESSION AND THE PORT's PARSER NEEDED A FRAME STACK,
# BECAUSE `parse` AND `close` NEED EACH OTHER AND **BEND REFUSES MUTUAL
# RECURSION** -- THE SAME WALL `tinybendygrad/uop/divandmod.bend`'s HEADER
# NAMES FOR `nest_by_factor`.  **SO THERE IS NO PARSER HERE.**
#
# AND THE ANSWER IS THE CANONICAL FORM OF THE TREE THE PORT ANSWERED WITH, AND
# IT IS THE PORT's OWN `P.dm_sh2`, SO THE ORACLE PRODUCES THE SAME FORM AND THE
# TWO DIFF AS STRINGS.

def CASES_DEFAULT() -> String: "gates/divandmod-cases.rows"

def CASES_OF(as: List<&1, String>) -> String:
  Maybe.default(&1, String, List.get(&1, String, as, 1n), CASES_DEFAULT())

# ---- THE CASE FILE's LINES.

def cs.keep.t(+s: String) -> Bool:
  Bool.and(Bool.not(String.eq(s, "")), Bool.not(String.starts_with(s, "#")))

def cs.keep(s: String) -> Bool:
  cs.keep.t(String.trim(s))

def cs.lines(s: String) -> List<&2, String>:
  List.filter(~String, ~cs.keep, String.lines(s))

# AND THE FIELDS, AND THERE IS NO `List.map` BECAUSE ITS ELEMENT TYPE IS THE
# **REFERENCE** AND NOT THE KIND: `List.get(a, -A, xs: List<a, A>, n)` (base.bend
# :1063) MAKES `a` THE ELEMENT TYPE, AND A `List<&2, String>` HAS ELEMENT TYPE
# `&2`.  SO THE FIELDS ARE READ BY INDEX AND NOT MAPPED.
def cs.split(s: String) -> List<&2, String>:
  String.split(s, '|')

def cs.trim(s: String) -> String:
  String.trim(s)

def cs.at(fs: List<&2, String>, k: Nat) -> String:
  cs.trim(Maybe.default(&2, String, List.get(&2, String, fs, k), ""))

# ---- THE NUMBERS.

def nm.chars(cs: List<&2, Char>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case c <> t: nm.chars(t, U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(c), 48)))

def nm.num(w: String) -> U32:
  nm.chars(String.to_list(w), 0)

def nm.of(fs: List<&2, String>, k: Nat) -> U32:
  nm.num(cs.at(fs, k))

# ---- THE GRAPH, AND IT IS THE ARM's OWN SHAPE: `(x%k + y + z)%c`.

def gp.param(+ar: O.Arena, w: String) -> O.Found:
  +sz = O.UOp.const(ar, O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(sz), O.OpsPARAM{}, [O.Found.i(sz)], O.AParam{P.dm_param(S.weakint(), 1, w)}, O.TNone{})


def gp.const(+ar: O.Arena, v: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})


def gp.alu(+ar: O.Arena, op: O.Op, a: U32, b: U32) -> O.Found:
  O.UOp.alu(ar, op, [a, b])


# AND THE TERM's NAME, AND IT IS `y` AND `z` FOR THE TERMS BESIDE THE INNER
# MOD -- MEASURED: THE FIRST DRAFT NAMED THE FIRST OF THEM `x` AND THE SUM WAS
# `x%k + x` AND NO LAW FIREED.
def gp.term.name(k: Nat) -> String:
  match k:
    case 0n: "y"
    case _: "z"

# AND THE SUM, AND IT IS `n` TERMS BESIDE THE INNER MOD, AND `n` IS A `Nat`
# AND NOT A `U32` BECAUSE THE COUNT PATTERNS ARE `0n` AND `1n++p`.
# AND THE SUM, AND IT IS `n` TERMS BESIDE THE INNER MOD, AND THE COUNT COMES
# **FIRST** BECAUSE BEND READS A CALL's ARGUMENTS LEFT TO RIGHT AND EACH IS
# PASSED UNCHANGED UNTIL ONE SHRINKS (MEASURED: "expected a call smaller than
# gp.sum(ar, 1n+p, acc)" -- THE ARENA GROWS AND SO IT IS NOT THE SHRINKING
# ONE).  AND THE ACCUMULATOR IS A `Found` AND NOT A `U32`, SO THE ARENA COMES
# WITH IT.

# AND THE TERM's NAME IS BY THE **COUNT SO FAR** AND NOT BY THE COUNT
# REMAINING, BECAUSE THE PATTERN `1n++p` PEELS FROM THE **FRONT** AND SO THE
# TERMS CAME OUT IN THE ORDER `z, y`.  MEASURED 2026-11-24: THE PORT's GRAPH
# WAS `MOD(ADD(ADD(MOD(Px,C8),Pz),Py),C2)` AND UPSTREAM's WAS
# `MOD(ADD(ADD(ADD(x,y),z),c0),c2)` -- THE SAME TERMS IN A DIFFERENT ORDER.
def gp.sum(n: Nat, +k: Nat, +acc: O.Found) -> O.Found:
  match n:
    case 0n: acc
    case 1n++p:
      +t = gp.param(O.Found.ar(acc), gp.term.name(k))
      +s = gp.alu(O.Found.ar(t), O.OpsADD{}, O.Found.i(acc), O.Found.i(t))
      gp.sum(p, Nat.add(k, 1n), s)

# AND THE GRAPH, AND `MODCONST` AND `DIVCONST` ARE THE ALL-CONST SHAPES.

def gp.modroot(+ar: O.Arena, a: U32, b: U32, ismod: Bool) -> O.Found:
  match ismod:
    case True{}: O.UOp.alu(ar, O.OpsMOD{}, [a, b])
    case False{}: O.UOp.alu(ar, O.OpsDIV{}, [a, b])

# ---- THE ANSWER, AND IT IS THE PORT's OWN CANONICAL FORM.


def gp.mod(+ar: O.Arena, k: U32, c: U32, n: Nat, d: U32, ismod: Bool) -> O.Found:
  +x = gp.param(ar, "x")
  +kc = gp.const(O.Found.ar(x), k)
  +m = gp.alu(O.Found.ar(kc), O.OpsMOD{}, O.Found.i(x), O.Found.i(kc))
  +s = gp.sum(n, 0n, m)
  +dc = gp.const(O.Found.ar(s), d)
  gp.modroot(O.Found.ar(dc), O.Found.i(s), O.Found.i(dc), ismod)


def gp.modconst(+ar: O.Arena, k: U32, c: U32, n: Nat, d: U32) -> O.Found:
  +a = gp.const(ar, k)
  +b = gp.const(O.Found.ar(a), c)
  +m = gp.alu(O.Found.ar(b), O.OpsMOD{}, O.Found.i(a), O.Found.i(b))
  +e = gp.const(O.Found.ar(m), 5)
  +s = gp.alu(O.Found.ar(e), O.OpsADD{}, O.Found.i(m), O.Found.i(e))
  +r = gp.const(O.Found.ar(s), d)
  gp.alu(O.Found.ar(r), O.OpsMOD{}, O.Found.i(s), O.Found.i(r))


def gp.divconst(+ar: O.Arena, k: U32, c: U32) -> O.Found:
  +a = gp.const(ar, k)
  +b = gp.const(O.Found.ar(a), c)
  gp.alu(O.Found.ar(b), O.OpsDIV{}, O.Found.i(a), O.Found.i(b))


# AND THE `divide_by_gcd` SHAPE, AND IT IS `(c0 + 2x) % (2x)` -- A NUMERATOR
# WHOSE CONSTANT TERM MAKES IT **NOT EXACTLY DIVISIBLE**, AND A DIVISOR THAT IS
# ITSELF A MUL SO THE GCD IS **2** AND NOT 1.
#
# AND THE SHAPE IS TWO SLOTS AND NOT FIVE: `k` IS THE MULTIPLIER (2) AND `n` IS
# THE CONSTANT TERM (0 OR 2).
def gp.gcd(+ar: O.Arena, k: U32, n: U32, ismod: Bool) -> O.Found:
  +x = gp.param(ar, "x")
  +kc = gp.const(O.Found.ar(x), k)
  +mx = gp.alu(O.Found.ar(kc), O.OpsMUL{}, O.Found.i(x), O.Found.i(kc))
  +cc = gp.const(O.Found.ar(mx), n)
  +s = gp.alu(O.Found.ar(cc), O.OpsADD{}, O.Found.i(cc), O.Found.i(mx))
  gp.modroot(O.Found.ar(s), O.Found.i(s), O.Found.i(mx), ismod)


# AND THE `factor_remainder` SHAPE, AND IT IS `(k*x + y) op d` -- A NUMERATOR
# WHOSE FIRST TERM IS A **MULTIPLE** OF `x` AND WHOSE SECOND TERM IS A **PARAM**
# AND NOT A CONST, SO THE CONSTANT BRANCH OF THE ARM (`(c:=u.const_factor())%
# y.val!=c`) DOES NOT FIRE FOR IT.
#
# AND THE MULTIPLIER IS `k` AND THE DIVISOR IS `d`.
# AND THE VARIABLE, AND IT IS `UOp.variable(name, lo, hi)` (ops.py:973-975) --
# A PARAM WITH **NO SRCS** (SO ITS `_shape` IS `()`), A `vmin_vmax` RANGE, AND
# THE **ALU** ADDRSPACE.  AND THE SHAPE IS THE POINT: `x.const_like(0)` IS A
# **BARE `CONST 0`** FOR A VARIABLE AND AN `EXPAND` FOR A SIZED PARAM.
def gp.var(+ar: O.Arena, nm: String, lo: U32, hi: U32) -> O.Found:
  F.g_mv_var(ar, H.i64_of_i32(lo), H.i64_of_i32(hi), nm)

# AND THE `factor_remainder` SHAPE, AND IT IS `(d*a + b) op d` WITH **`d` A
# VARIABLE** -- AND THE VARIABLE IS THE WHOLE POINT, BECAUSE A CONST DIVISOR
# PUTS THE ARM BEHIND `divide_by_gcd`, WHOSE `gcd` IS AN `EXPAND` AND NOT A
# `CONST`, AND UPSTREAM THEN **RAISES** (divandmod.py:72-76).
# AND THE EXTRA CONST TERMS, AND THEY ARE `c(k+i)` FOR `i` IN `0..n`.
def gp.fr.terms.go(n: Nat, +i: U32, +k: U32, +ar: O.Arena, +s: O.Found) -> O.Found:
  match n:
    case 0n: s
    case 1n++p:
      +t = gp.const(O.Found.ar(s), U32.add(k, i))
      +n2 = gp.alu(O.Found.ar(t), O.OpsADD{}, O.Found.i(s), O.Found.i(t))
      gp.fr.terms.go(p, U32.add(i, 1), k, O.Found.ar(n2), n2)

def gp.fr.terms(+ar: O.Arena, +s: O.Found, n: Nat, +k: U32) -> O.Found:
  gp.fr.terms.go(n, 0, k, ar, s)

# AND THE `factor_remainder` ARM's CONSTANT BRANCH, AND IT IS
# `(k*a + b) op c` WITH `k` **NOT** DIVIDING `c` -- AND THE SECOND TERM IS A
# **PARAM** AND NOT A CONST, SO THE EARLIER ARMS DO NOT CATCH IT.
def gp.frc(+ar: O.Arena, k: U32, c: U32, ismod: Bool) -> O.Found:
  +a = gp.var(ar, "a", 0, 100)
  +b = gp.var(O.Found.ar(a), "b", 0, 100)
  +kc = gp.const(O.Found.ar(b), k)
  +mx = gp.alu(O.Found.ar(kc), O.OpsMUL{}, O.Found.i(a), O.Found.i(kc))
  +s = gp.alu(O.Found.ar(mx), O.OpsADD{}, O.Found.i(mx), O.Found.i(b))
  +dc = gp.const(O.Found.ar(s), c)
  gp.modroot(O.Found.ar(dc), O.Found.i(s), O.Found.i(dc), ismod)

# AND THE `nested_div` SHAPE, AND IT IS `(x % kc) // c` WITH `x` A PARAM AND
# `kc` AND `c` CONSTs -- AND `c` DIVIDES `kc` SO THE ARM FIRES
# (divandmod.py:23), AND THE ANSWER IS `(x // c) % (kc//c)`.
def gp.nd(+ar: O.Arena, kc: U32, c: U32, ismod: Bool) -> O.Found:
  +x = gp.param(ar, "x")
  +k = gp.const(O.Found.ar(x), kc)
  +m = gp.alu(O.Found.ar(k), O.OpsMOD{}, O.Found.i(x), O.Found.i(k))
  +d = gp.const(O.Found.ar(m), c)
  gp.modroot(O.Found.ar(d), O.Found.i(m), O.Found.i(d), ismod)

# AND THE `factor_remainder` SHAPE, AND IT IS `(d*a*k + b + ...) op (c*d)` WITH
# **`d` A VARIABLE** -- AND THE VARIABLE IS THE WHOLE POINT, BECAUSE A CONST
# DIVISOR PUTS THE ARM BEHIND `divide_by_gcd`, WHOSE `gcd` IS AN `EXPAND` AND
# NOT A `CONST`, AND UPSTREAM THEN **RAISES** (divandmod.py:72-76).
#
# AND THE SHAPE IS UPSTREAM's OWN TEST's SHAPE (test/null/test_uop_symbolic.py
# :584-590) AND NOT A NEW ONE.
# AND THE MULTIPLIER, AND IT IS `x*k` AND THE `k=1` CASE IS THE NODE ITSELF --
# AND UPSTREAM's OWN `x*1` IS **NOT** FOLDED AWAY IN THE ANSWER, SO THE PORT
# MUST NOT FOLD IT EITHER.  MEASURED: UPSTREAM ANSWERS `(d*a+b)//d` WITH
# `ADD(c0,MUL(c1,a))` -- **THE `1` IS THERE**.
# AND THE `k=1` CASE IS THE NODE ITSELF **RE-HOMED INTO THE GIVEN ARENA**,
# BECAUSE AN INDEX IS VALID IN A DESCENDANT AND NOT IN AN ANCESTOR, AND THE
# CALLER READS IT IN THE ARENA IT PASSED.  MEASURED 2026-11-25: WITHOUT THE
# RE-HOMING THE PORT ANSWERED `nofold`.
def gp.fr.mul.go(one: Bool, +ar: O.Arena, +x: O.Found, +y: O.Found) -> O.Found:
  match one:
    case True{}: O.Found{ar, O.Found.i(x)}
    case False{}: gp.alu(ar, O.OpsMUL{}, O.Found.i(x), O.Found.i(y))

def gp.fr.mul(+ar: O.Arena, +x: O.Found, k: U32, +y: O.Found) -> O.Found:
  gp.fr.mul.go(U32.is_eq(k, 1), ar, x, y)

# AND THE `factor_remainder` SHAPE, AND IT IS `(d*a*k + b + ...) op (c*d)` WITH
# **`d` A VARIABLE** -- AND THE VARIABLE IS THE WHOLE POINT, BECAUSE A CONST
# DIVISOR PUTS THE ARM BEHIND `divide_by_gcd`, WHOSE `gcd` IS AN `EXPAND` AND
# NOT A `CONST`, AND UPSTREAM THEN **RAISES** (divandmod.py:72-76).
#
# AND THE SHAPE IS UPSTREAM's OWN TEST's SHAPE (test/null/test_uop_symbolic.py
# :584-590) AND NOT A NEW ONE.
def gp.fr(+ar: O.Arena, +k: U32, +c: U32, n: Nat, d: U32, ismod: Bool) -> O.Found:
  +kc = gp.const(ar, k)
  +a = gp.var(O.Found.ar(kc), "a", 0, 10)
  +dv = gp.var(O.Found.ar(a), "d", 1, 10)
  +b = gp.var(O.Found.ar(dv), "b", 0, 10)
  +ad = gp.alu(O.Found.ar(b), O.OpsMUL{}, O.Found.i(a), O.Found.i(dv))
  +ak = gp.fr.mul(O.Found.ar(ad), ad, k, kc)
  +s = gp.alu(O.Found.ar(ak), O.OpsADD{}, O.Found.i(ak), O.Found.i(b))
  +s2 = gp.fr.terms(O.Found.ar(s), s, n, k)
  +cc = gp.const(O.Found.ar(s2), c)
  +den = gp.fr.mul(O.Found.ar(cc), dv, c, cc)
  gp.modroot(O.Found.ar(den), O.Found.i(s2), O.Found.i(den), ismod)


# AND THE `fold_divmod_congruence` SHAPE, AND IT IS `(k*a + [b] + d) op c` WITH
# `a` AND `b` **VARIABLES** IN [0, 1] -- AND THE RANGE IS THE POINT: THE ARM's
# TEST IS `rem.vmin//c == rem.vmax//c`, SO THE RANGE OF THE NUMERATOR DECIDES
# WHETHER THE ARM FIRES.
#
# AND THE EXTRA TERMS, AND THEY ARE `b` AND `z` AND NOT `y` AND `z`, SO THE
# ORACLE's READER AND THIS ONE NAME THEM THE SAME WAY.
def gp.cg.name(k: Nat) -> String:
  match k:
    case 0n: "b"
    case _: "z"

def gp.cg.terms.go(n: Nat, +k: Nat, +s: O.Found) -> O.Found:
  match n:
    case 0n: s
    case 1n++p:
      +t = gp.var(O.Found.ar(s), gp.cg.name(k), 0, 1)
      +s2 = gp.alu(O.Found.ar(t), O.OpsADD{}, O.Found.i(s), O.Found.i(t))
      gp.cg.terms.go(p, Nat.add(k, 1n), s2)

def gp.cg.terms(+ar: O.Arena, n: Nat, +s: O.Found) -> O.Found:
  gp.cg.terms.go(n, 0n, s)

def gp.cg(+ar: O.Arena, k: U32, c: U32, n: Nat, d: U32, ismod: Bool) -> O.Found:
  +a = gp.var(ar, "a", 0, 1)
  +kc = gp.const(O.Found.ar(a), k)
  +mx = gp.alu(O.Found.ar(kc), O.OpsMUL{}, O.Found.i(a), O.Found.i(kc))
  +s = gp.cg.terms(O.Found.ar(mx), n, mx)
  +dc = gp.const(O.Found.ar(s), d)
  +num = gp.alu(O.Found.ar(dc), O.OpsADD{}, O.Found.i(s), O.Found.i(dc))
  +cc = gp.const(O.Found.ar(num), c)
  gp.modroot(O.Found.ar(cc), O.Found.i(num), O.Found.i(cc), ismod)


def gp.root(+ar: O.Arena, op: String, k: U32, c: U32, n: Nat, d: U32) -> O.Found:
  match op:
    case "MODCONST": gp.modconst(ar, k, c, n, d)
    case "DIVCONST": gp.divconst(ar, k, c)
    case "GCDMOD": gp.gcd(ar, k, U32.from_nat(n), True{})
    case "GCDDIV": gp.gcd(ar, k, U32.from_nat(n), False{})
    case "FRMOD": gp.fr(ar, k, c, n, d, True{})
    case "FRDIV": gp.fr(ar, k, c, n, d, False{})
    case "ND": gp.nd(ar, k, c, False{})
    case "FRC": gp.frc(ar, k, c, False{})
    case "FRCM": gp.frc(ar, k, c, True{})
    case "CG": gp.cg(ar, k, c, n, d, False{})
    case "CGM": gp.cg(ar, k, c, n, d, True{})
    case "DIV": gp.mod(ar, k, c, n, d, False{})
    case _: gp.mod(ar, k, c, n, d, True{})


# ---- THE ANSWER, AND IT IS THE PORT's OWN CANONICAL FORM.
#
# AND THE THREE VERDICTS ARE THE ORACLE's THREE AND NOT SYNONYMS: `RAISED` FOR
# THE ZERO DIVISOR, `nofold` FOR NO REWRITE, AND `ANSWERED <form>` FOR THE TREE
# THE PORT REWROTE TO.
#
# AND THE ZERO TEST IS REPORTED ONLY WHERE PYTHON REACHES
# `P.fold_divmod_general` AT ALL, WHICH IS WHERE **RULE 2 CLAIMS THE NODE** --
# A TRUNCMOD ROOT IS CLAIMED BY NOBODY, SO PYTHON ANSWERS `None` THERE AND
# NEVER RAISES.  THE OP SET IS READ FROM `P.dm_table()` RATHER THAN SPELLED
# HERE, SO A WIDER RULE 2 MOVES THE WORD WITH IT.

def dr.two.go(m: Maybe<&2, O.PMEntry>) -> List<&2, O.Op>:
  match m:
    case Some{e}: O.PMEntry.ops(e)
    case None{}: Nil{}

def dr.two() -> List<&2, O.Op>:
  dr.two.go(List.get(&2, O.PMEntry, O.PMEntrys.es(P.dm_table()), 2n))

def dr.reach(+r: O.Found) -> Bool:
  O.pm_claimed(dr.two(), O.Found.ar(r), O.Found.i(r))

# AND THE CANONICAL FORM, AND IT IS A **FULL** RENDER AND NOT THE PORT's OWN
# `P.dm_sh2`.  MEASURED 2026-11-24: `dm_sh2` IS A **TWO-LEVEL** RENDER -- THE
# ROOT WITH ITS CHILDREN's LABELS -- SO IT LOSES THE GRANDCHILDREN, AND A
# DIFFERENTIAL ROW THAT LOSES PART OF THE TREE IS NOT A DIFFERENTIAL ROW.  SO
# THE FORM IS RENDERED HERE, IN FULL, AND THE ORACLE PRODUCES THE SAME FORM.
#
# AND THE FORM IS THE PORT's OWN LABELS: `Ops.NAME` FOR AN OP, `P<name>` FOR A
# PARAM AND `CONST(v)` FOR A CONST -- `P.dm_lab`'s THREE FORMS.
def dr.lab(+ar: O.Arena, u: U32) -> String:
  P.dm_lab(ar, u)

# AND IT IS **ONE** RECURSIVE DEF AND NOT TWO, BECAUSE `form` AND `form.go`
# NEED EACH OTHER AND BEND REFUSES MUTUAL RECURSION.  AND THE FUEL IS THE
# ARENA's NODE COUNT, AND IT SHRINKS, BECAUSE BEND READS A CALL's ARGUMENTS
# LEFT TO RIGHT AND EACH IS PASSED UNCHANGED UNTIL ONE SHRINKS -- MEASURED:
# "expected a call smaller than dr.form(ar, u, leaf)".
# AND A PARAM AND A CONST ARE **LEAVES** AND NOT NODES WITH CHILDREN, AND THE
# REASON IS MEASURED: A PARAM's ONE SRC IS ITS **SIZE CONST** AND NOT A VALUE
# (`ops.py:62` -- "The flat size n is stated as a concrete weakint Const in
# src"), SO RENDERING IT WOULD PUT THE SIZE IN THE FORM AND THE SIZE IS NOT
# PART OF THE CLAIM.
def dr.leafof(+ar: O.Arena, +u: U32) -> Bool:
  Bool.or(O.eq_op(O.Arena.op(ar, u), O.OpsCONST{}), O.eq_op(O.Arena.op(ar, u), O.OpsPARAM{}))

def dr.form.go(fuel: Nat, leaf: Bool, +ar: O.Arena, +u: U32) -> String:
  match fuel:
    case 0n: dr.lab(ar, u)
    case 1n++p:
      match leaf:
        case True{}: dr.lab(ar, u)
        case False{}: String.concat([dr.lab(ar, u), "(", dr.form.go(p, dr.leafof(ar, O.Arena.src0(ar, u)), ar, O.Arena.src0(ar, u)),
                                     ",", dr.form.go(p, dr.leafof(ar, O.Arena.src(ar, u, 1)), ar, O.Arena.src(ar, u, 1)), ")"])

def dr.form(+ar: O.Arena, +u: U32) -> String:
  dr.form.go(O.Arena.budget(ar), dr.leafof(ar, u), ar, u)

# AND THE ANSWER IS THE **VALUE** AND NOT THE TREE, AND THE REASON IS MEASURED:
# UPSTREAM's `canonicalize` REWRITES `SUB` INTO `ADD(x, MUL(MUL(q,y),C(-1)))`
# (THE HEADER's DIVERGENCE B), SO THE TWO TREES DIFFER WHILE THE VALUES ARE
# EQUAL -- AND A ROW THAT COMPARES TREES ON A CASE WHERE THE PORT KEEPS A
# `SUB` AND PYTHON DOES NOT IS A ROW THAT CAN NEVER PASS.  THE PORT's OWN
# `P.dm_point.sub` BUILDS `x - q*y` AND UPSTREAM's ANSWER IS THE EXPANDED
# ONE.
#
# AND THE ARITHMETIC IS 32-BIT HERE AND UNBOUNDED IN PYTHON, AND THAT IS THE
# POINT: tinygrad CONSTs ARE MATHEMATICAL PYTHON INTS, SO `1 % -2147483648` IS
# 1 WHILE THE PORT's `MUL(-1, INT_MIN)` IS ALREADY 2^31 BEFORE THE SUB.
def dr.ival(+ar: O.Arena, u: U32) -> U32:
  P.dm_ival(P.dm_val(ar, u))

def dr.val.kind2(isconst: Bool, issub: Bool, ismul: Bool) -> Nat:
  match isconst:
    case True{}: 0n
    case False{}:
      match issub:
        case True{}: 1n
        case False{}:
          match ismul:
            case True{}: 2n
            case False{}: 3n

def dr.val.kind(+ar: O.Arena, +u: U32) -> Nat:
  dr.val.kind2(O.eq_op(O.Arena.op(ar, u), O.OpsCONST{}),
                O.eq_op(O.Arena.op(ar, u), O.OpsSUB{}),
                O.eq_op(O.Arena.op(ar, u), O.OpsMUL{}))

# AND IT IS **ONE** RECURSIVE DEF AND NOT TWO, BECAUSE `val` AND `bin` NEED
# EACH OTHER AND BEND REFUSES MUTUAL RECURSION, AND THE FUEL IS THE ARENA's
# NODE COUNT AND IT SHRINKS.
def dr.hit(on: U32, +ar: O.Arena, +i: U32) -> String:
  match on:
    case 0: "nofold"
    case _: String.concat(["ANSWERED ", dr.form(ar, i)])

def dr.ans.go(rz: Bool, +h: P.Hit, +ar: O.Arena) -> String:
  match rz:
    case True{}: "RAISED ZeroDivisionError"
    case False{}: dr.hit(P.Hit.on(h), ar, P.Hit.i(h))

def dr.ans.d(+ar: O.Arena, +r: O.Found) -> String:
  +h = P.div_and_mod_symbolic(F.folded(ar), O.Found.i(r))
  String.concat(["rz=", Bool.show(Bool.and(dr.reach(r), P.dm_zero(ar, O.Found.i(r)))),
                  " on=", U32.show(P.Hit.on(h)),
                  " i=", U32.show(P.Hit.i(h)),
                  " ar_ne=", Bool.show(U32.is_eq(O.Arena.next(P.Hit.ar(h)), O.Arena.next(ar))),
                  " form=", P.dm_sh2(P.Hit.ar(h), P.Hit.i(h)),
                  " r_ar_ne=", Bool.show(U32.is_eq(O.Arena.next(O.Found.ar(r)), O.Arena.next(ar))),
                  " rop=", O.Ops.name.of(O.Arena.op(O.Found.ar(r), O.Found.i(r))),
                  " rsrcs=", U32.show(O.Arena.nsrc(O.Found.ar(r), O.Found.i(r)))])

# AND THE ARENA THE ANSWER IS READ IN IS **THE ONE THE FOLD GREW** AND NOT THE
# ONE THE GRAPH WAS BUILT IN: `P.Hit` CARRIES `ar`, `i` AND `on`, AND `ar` IS
# THE ARENA THE REWRITE LANDED IN.  MEASURED 2026-11-24: A FIRST DRAFT READ
# `P.Hit.i(h)` IN THE ORIGINAL ARENA AND EVERY ANSWER WAS `nofold`.
# AND THE ARENA IS **THE ROOT's** AND NOT THE ONE THE CALLER BOUND, BECAUSE
# THE ARENA GROWS BY **RETURNING A NEW ONE** (`UOp.new.of(+ar, +made, ...)`,
# ops.bend:1843) AND SO THE CALLER's `+ar` BINDING IS STALE.  MEASURED
# 2026-11-24: A FIRST DRAFT READ `F.folded(ar)` AND EVERY ANSWER WAS `nofold`,
# AND THE PROBE SAID `F.folded(O.Found.ar(r))` FIRED.
def dr.ans(+ar: O.Arena, +r: O.Found) -> String:
  +h = P.div_and_mod_symbolic(F.folded(O.Found.ar(r)), O.Found.i(r))
  dr.ans.go(Bool.and(dr.reach(r), P.dm_zero(O.Found.ar(r), O.Found.i(r))), h, P.Hit.ar(h))

def dr.diag(+ar: O.Arena, +r: O.Found) -> String:
  +fx = F.folded(O.Found.ar(r))
  +h = P.div_and_mod_symbolic(fx, O.Found.i(r))
  String.concat(["reach=", Bool.show(dr.reach(r)),
                  " zero=", Bool.show(P.dm_zero(O.Found.ar(r), O.Found.i(r))),
                  " weak=", Bool.show(P.dm_weak(fx, O.Found.i(r))),
                  " hit=", U32.show(P.Hit.on(h))])

def dr.show.go(l: List<&2, U32>, acc: String) -> String:
  match l:
    case Nil{}: acc
    case h <> t: dr.show.go(t, String.concat([acc, U32.show(h), " "]))

def dr.show(l: List<&2, U32>) -> String:
  dr.show.go(l, "")

def dr.split(+ar: O.Arena, +r: O.Found) -> String:
  dr.form(O.Found.ar(r), O.Found.i(r))

def dr.one(+fs: List<&2, String>) -> String:
  +ar = O.Arena.empty()
  +r = gp.root(ar, cs.at(fs, 1n), nm.of(fs, 2n), nm.of(fs, 3n), U32.to_nat(nm.of(fs, 4n)), nm.of(fs, 5n))
  dr.ans(ar, r)

def dr.name(fs: List<&2, String>) -> String:
  cs.at(fs, 0n)

# ---- THE ROWS, AND ONE PER CASE AND IN THE FILE's ORDER.

def dr.rows.go(ls: List<&2, String>) -> IO(Unit):
  match ls:
    case Nil{}: IO.pure(Unit, Unit{})
    case +l <> t:
      do IO<Unit>:
        u : Unit <- IO.print(String.concat([dr.name(cs.split(l)), "=", dr.one(cs.split(l))]))
        v : Unit <- dr.rows.go(t)
        IO.pure(Unit, u)

def dr.rows(ls: List<&2, String>) -> IO(Unit):
  dr.rows.go(ls)

# ---- THE FILE.

def dr.closed(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(f)
    IO.pure(String, s)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(CASES_OF(as), "r"))
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4000000)
    s : String <- dr.closed(m)
    u : Unit <- dr.rows(cs.lines(s))
    return Unit{}
