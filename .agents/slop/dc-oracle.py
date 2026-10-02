#!/usr/bin/env python3
# dc-oracle.py -- the ORACLE for tinybendygrad/codegen/decomp.bend.
#
# It prints what PYTHON's two decomp tables do, in the exact two-level shape the
# Bend gate prints, so the two are diffed row for row. Python is the reference;
# nothing here is a reimplementation.
#
#   nrules_s / nrules_l / nrules_l_noidiv   op.py:66 and op.py:81, three counts
#   rejsN= / rejlN=                         `early_reject`, measured not guessed
#   on_<f> / tag_<f> / out_<f>              fired?, WHICH rule, and its tree
#   nroots=<n>                              the fixture COUNT
#
# TWO PRINT-SHAPE DECISIONS, both named, and neither is a reimplementation:
#
# 1. PROMOTION CASTS ARE ERASED. `mixin/elementwise.py`'s `_broadcasted` inserts
#    `CAST(bool -> int)` before an `ADD`/`SUB`/`MUL` with a bool operand, and
#    `UOp.__init__`'s `dtype_from_uop` inserts `CAST(int -> bool)` on a comparison
#    result. `ops.bend`'s `UOp.new` runs NEITHER, which is `symbolic.bend`'s wall
#    2 and `divandmod.bend`'s divergence A. So the port's trees are the ones
#    Python prints with the promotion CASTs deleted, and this printer deletes
#    them with the same rule: a CAST whose arg differs from its src's dtype.
#    Nothing else is deleted, and `out_l5` is the row where a reader checks.
#
# 2. `C(v)` is a signed decimal. Python's repr writes `CONST(True)` for a bool
#    CONST; the port has ONE integer Const type, so a bool const is `C(1)`.
#    Exactly one rule can tell the two apart -- late rule 12, whose pattern is
#    `x.ne(y).logical_not()` and whose `logical_not` puts the bool `True` in the
#    CMPNE's src1 -- and the port tests that position STRUCTURALLY, so the print
#    is a label and not the test.
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp.op import get_simplifying_rewrite_patterns, get_late_rewrite_patterns

ALL = tuple(Ops)


def P(nm, dt, lo, hi): return UOp.variable(nm, lo, hi, dt)


def pi(): return P("i", dtypes.i32, -20, 20)
def pz(): return P("z", dtypes.i32, 0, 100)
def pu(): return P("u", dtypes.u32, 0, 40)
def pb(): return P("b", dtypes.bool, 0, 1)
def pf(): return P("f", dtypes.f32, 0.0, 1.0)
def qf(): return P("g", dtypes.f32, 0.0, 1.0)
def pj(): return P("j", dtypes.i32, -20, 20)


def K(v): return UOp.const(v)
def lnot(x): return x.cast(dtypes.bool).ne(K(True))
def fdiv(a, b): return UOp(Ops.FDIV, src=(a, b))


# THE FIXTURE LIST IS THE CONTRACT. `nroots` in the Bend gate is this list's
# length and the two files are diffed row for row, so a fixture added here and
# not there moves `nroots` and nothing else -- which is the point of the row.
def fixtures():
    x, z, u, b, f, g, y = pi(), pz(), pu(), pb(), pf(), qf(), pj()
    A = lambda *s: UOp(Ops.AND, src=tuple(s))
    return [
        # --- SIMPLIFYING, op.py:66-78, four rules. s0 and s1 BOTH claim
        # FLOORDIV(x, const) and answer DIFFERENTLY: s0 is one SHR, s1 is five
        # nodes. s0/s1 and s2/s3 are the two-rules-one-node fixtures the brief
        # asks for, and s2/s5 are the `powers_of_two.get(c,0)`-IS-FALSY pair.
        ("s0", "s", lambda: x // K(4)),          # -> SHR(Pi,C(2)), rule 0
        ("s1", "s", lambda: x // K(3)),          # -> the general form, rule 1
        ("s2", "s", lambda: x // K(1)),          # powers_of_two[1]==0 is FALSY -> rule 1
        ("s3", "s", lambda: x % K(4)),           # -> AND(Pi,C(3)), rule 2
        ("s4", "s", lambda: x % K(3)),           # -> the general form, rule 3
        ("s5", "s", lambda: x % K(1)),           # 1 IS in powers_of_two -> AND(Pi,C(0))
        ("s6", "s", lambda: x % K(0)),           # 0 is NOT -> the general form
        ("s7", "s", lambda: u // K(3)),          # uint is not dtypes.ints -> rule 1
        ("s8", "s", lambda: x // K(2**31)),      # a power of two AND a legal CONST
        # --- LATE, op.py:81-126, eighteen rules.
        ("l0", "l", lambda: A(lnot(b), lnot(b))),                   # rule 0
        ("l1", "l", lambda: x * K(4)),                              # rule 1
        ("l2", "l", lambda: x * K(1)),                              # rules 1 AND 6 claim; both skip
        ("l3", "l", lambda: x * K(-1)),                             # rule 6
        ("l4", "l", lambda: x * K(2147483647)),                     # a CONST, not a power of two
        ("l5", "l", lambda: x * K(5)),                              # a CONST, not a power of two
        ("l6", "l", lambda: u.alu(Ops.CDIV, K(4))),                 # rule 2
        ("l7", "l", lambda: x.alu(Ops.CDIV, K(4))),                 # rule 3 BEATS rule 4
        ("l8", "l", lambda: z.alu(Ops.CDIV, K(4))),                 # the same, non-negative
        ("l9", "l", lambda: z.alu(Ops.CDIV, K(3))),                 # rule 4 alone: fast_idiv
        ("l10", "l", lambda: z.alu(Ops.CMOD, K(3))),                # rule 5 alone: fast_idiv
        ("l11", "l", lambda: x + x.alu(Ops.NEG)),                    # rule 7
        ("l12", "l", lambda: lnot(x < K(5))),                       # rule 8
        ("l13", "l", lambda: lnot(K(5) < x)),                       # rule 9
        ("l14", "l", lambda: (x * K(-1)) < (y * K(3))),              # rule 10
        ("l15", "l", lambda: (x * K(-1)) < K(5)),                   # rule 11
        ("l16", "l", lambda: A(K(1) < x, x < K(3))),                # rule 12, x is ONE node
        ("l17", "l", lambda: A(K(1) < x, y < K(3))),                # rule 12, x is TWO: NO match
        ("l18", "l", lambda: lnot(x.ne(y))),                        # rule 13
        ("l19", "l", lambda: (x * y) + x),                          # rule 14
        ("l20", "l", lambda: (x * y) + K(4)),                       # rule 14, the swapped ADD
        ("l21", "l", lambda: x.alu(Ops.SHL, K(3)) + x),             # rule 15
        ("l22", "l", lambda: f.reciprocal()),                       # rule 16
        ("l23", "l", lambda: f * fdiv(K(1.0), g)),                  # rule 17
        ("l24", "l", lambda: A(K(1) < x, x < K(4))),                # c1+1 != c2-1 -> None
        # the two COMMUTATIVITY rows: `UPat.alu` (ops.py:1533) passes a LIST for
        # an op in `GroupOp.Commutative`, so MUL is an is_any over BOTH orders
        # and a hand-written matcher that reads only src1 loses these.
        ("l25", "l", lambda: K(4) * x),                              # rule 1, CONST on the LEFT
        ("l26", "l", lambda: (K(-1) * x) < (K(3) * y)),              # rule 10, both MULs flipped
        # the three `fast_idiv` guards that ARE ported, op.py:21-22
        ("l27", "l", lambda: z.alu(Ops.CDIV, K(200))),               # vmax 100 < 200 -> C(0)
        ("l28", "l", lambda: z.alu(Ops.CDIV, K(0))),                 # d <= 0
        ("l29", "l", lambda: x.alu(Ops.CDIV, K(3))),                 # x.vmin = -20 < 0
    ]


# The THREEFRY fixture, which lives in the OTHER `ops` variant: op.py:77 only
# appends the rule `if Ops.THREEFRY not in ops`, so it is in the five-rule table
# and NOT in the four-rule one Python builds for `tuple(Ops)`.
def tf_fixture():
    return UOp(Ops.THREEFRY, src=(UOp.const(0x0123456789abcdef), UOp.const(0xfedcba9876543210)))


def uncast(v):
    """the promotion CAST, deleted. Same rule as divergence 1 in the header."""
    while v.op is Ops.CAST and v.arg != v.src[0].dtype: v = v.src[0]
    return v


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        # a bool CONST prints as the port's one integer Const, and a float CONST
        # through the port's `H.f32_show`, which spells 1.0 as `1`. `%g` agrees
        # with `H.f32_show` on 1.0 -- the only float CONST in this file -- and
        # would NOT agree on a non-integral one. Named in the header.
        a = int(v.arg) if isinstance(v.arg, bool) else v.arg
        return f"C({a:g})" if isinstance(a, float) else f"C({a})"
    if v.op is Ops.PARAM: return f"P{v.arg.name}"
    return v.op.name


def sh1(v):
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(lab(s) for s in v.src)})"


def show(v):
    if v is None: return "none"
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(sh1(s) for s in v.src)})"


def main():
    ps = get_simplifying_rewrite_patterns(ALL)
    pl = get_late_rewrite_patterns(ALL, False)
    fx = fixtures()
    print(f"nrules_s={len(ps.patterns)}")
    print(f"nrules_l={len(pl.patterns)}")
    print(f"nrules_l_noidiv={len(get_late_rewrite_patterns(ALL, True).patterns)}")
    print(f"nroots={len(fx)}")
    for i, (p, f) in enumerate(pl.patterns):
        print(f"rejl{i}={','.join(sorted(o.name for o in p.early_reject)) or '-'}")
    for i, (p, f) in enumerate(ps.patterns):
        print(f"rejs{i}={','.join(sorted(o.name for o in p.early_reject)) or '-'}")
    for nm, which, build in fx:
        pm = ps if which == "s" else pl
        u = build()
        ler = {s.op for s in u.src}
        idx = {id(p): j for j, (p, f) in enumerate(pm.patterns)}
        fired, ret = -1, None
        for p, match, er in pm.pdict.get(u.op, []):
            if not er.issubset(ler): continue
            for st in p.match(u, {}):
                r = match(u, st)
                if r is not None and r is not u:
                    fired, ret = idx[id(p)], r
                    break
            if fired >= 0: break
        assert (fired >= 0) == (pm.rewrite(u) is not None), f"{nm}: tag scan disagrees with rewrite"
        print(f"on_{nm}={1 if ret is not None else 0}")
        print(f"tag_{nm}={fired if fired >= 0 else 'none'}")
        print(f"out_{nm}={show(ret)}")
    # the THREEFRY rule, in the `THREEFRY not in ops` table -- op.py:77
    t = tf_fixture()
    p3f = get_simplifying_rewrite_patterns(tuple(o for o in Ops if o is not Ops.THREEFRY))
    print(f"nrules_s_no3f={len(p3f.patterns)}")
    ret = p3f.rewrite(t)
    print(f"on_s9={1 if ret is not None else 0}")
    print(f"out_s9={show(ret)}")


if __name__ == "__main__":
    main()
