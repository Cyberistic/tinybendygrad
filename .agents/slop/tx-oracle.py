#!/usr/bin/env python3
# tx-oracle.py -- the ORACLE for tinybendygrad/codegen/transcendental.bend.
# Renders the same rows the Bend gate prints. Python is the reference.
import sys, struct, collections
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import transcendental as T


def uncast(v):
    """the promotion CAST, deleted. Same rule as decomp.bend divergence A."""
    while v.op is Ops.CAST and v.arg != v.src[0].dtype: v = v.src[0]
    return v


def fbits(x):
    if x != x: return "nan"
    if x == float("inf"): return "inf"
    if x == float("-inf"): return "-inf"
    return str(struct.unpack("<I", struct.pack("<f", x))[0])


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        a = v.arg
        if isinstance(a, bool): return f"C({int(a)})"
        if isinstance(a, float): return f"F{fbits(a)}"
        return f"C({a})"
    if v.op is Ops.PARAM: return f"P{v.arg.name}"
    return v.op.name


def sh1(v):
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(lab(s) for s in v.src)})"


def show(v):
    if v is None: return "none"
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(sh1(s) for s in v.src)})"


class Pair(list):
    pass


def walk(v, acc):
    if isinstance(v, Pair):
        for s in v: walk(s, acc)
        return
    v = uncast(v)
    acc.append(v)
    for s in v.src: walk(s, acc)


def count(v):
    acc = []
    walk(v, acc)
    return len(acc)


def hist(v):
    acc = []
    walk(v, acc)
    c = collections.Counter(u.op.name for u in acc)
    return ",".join(f"{k}:{c[k]}" for k in sorted(c))


def dfp(dt, nm="d"):
    return UOp.variable(nm, 0.0, 100.0, dt)


def fx(dt, nm="x"):
    return UOp.variable(nm, -1.0, 1.0, dt)


def show2(v):
    if isinstance(v, Pair): return f"({show(v[0])}|{show(v[1])})"
    return show(v)


def cnt2(v):
    if isinstance(v, Pair): return count(v[0]) + count(v[1])
    return count(v)


def hist2(v):
    if isinstance(v, Pair): return hist(v[0]) + ";" + hist(v[1])
    return hist(v)


def rows(nm, v):
    print(f"out_{nm}={show2(v)}")
    print(f"cn_{nm}={cnt2(v)}")
    print(f"hs_{nm}={hist2(v)}")


def main():
    for dt, dn in ((dtypes.f32, "f32"), (dtypes.f16, "f16"), (dtypes.f64, "f64")):
        d = dfp(dt)
        x = fx(dt)
        print(f"== {dn} ==")
        print(f"mt_{dn}={T.mantissa_bits(dt)}")
        print(f"eb_{dn}={T.exponent_bias(dt)}")
        print(f"em_{dn}={T.exponent_mask(dt)}")
        rows(f"rintk_{dn}", T.rintk(d))
        rows(f"pow2if_{dn}", T.pow2if(UOp.const(3, dtypes.i32), dt))
        rows(f"ilogb_{dn}", T.ilogb2k(d))
        rows(f"ldexp3_{dn}", T.ldexp3k(d, UOp.const(-2, dt)))
        rows(f"ldexp2_{dn}", T.ldexp2k(d, UOp.const(-2, dtypes.i32)))
        rows(f"frexp_{dn}", Pair(T.frexp(d)))
        rows(f"cw_{dn}", Pair(T.cody_waite_reduction(d)))
        rows(f"ph_{dn}", Pair(T.payne_hanek_reduction(d)))
        rows(f"sp_{dn}", T.sin_poly(d))
        rows(f"sps_{dn}", T.sin_poly_small(x, UOp.const(1, dtypes.i32)))
        rows(f"spl_{dn}", T.sin_poly_large(x, UOp.const(2, dtypes.i32)))
        rows(f"xsinf_{dn}", T.xsin(d, fast=True))
        rows(f"xsin_{dn}", T.xsin(d))
        rows(f"xexp2_{dn}", T.xexp2(d))
        rows(f"xlog2_{dn}", T.xlog2(d))
        rows(f"xpow_{dn}", T.xpow(d, UOp.const(2, dt)))
        # switch_over is a PARAMETER: the default 30.0 and a different one differ
        rows(f"xsin7_{dn}", T.xsin(d, switch_over=7.0))
    # THE TABLE -- op.py:267-277. `ops` and `force` are PARAMETERS.
    ALL = tuple(Ops)
    NON = tuple(o for o in Ops if o not in (Ops.EXP2, Ops.LOG2, Ops.SIN))
    NOSQ = tuple(o for o in Ops if o is not Ops.SQRT)
    print(f"n_all={len(T.get_transcendental_patterns(ALL, False).patterns)}")
    print(f"n_non={len(T.get_transcendental_patterns(NON, False).patterns)}")
    print(f"n_nosq={len(T.get_transcendental_patterns(NOSQ, False).patterns)}")
    print(f"n_force={len(T.get_transcendental_patterns(ALL, True).patterns)}")
    print(f"n_empty={len(T.get_transcendental_patterns(tuple(), False).patterns)}")
    p = T.get_transcendental_patterns(NON, False).patterns
    for i, (pat, f) in enumerate(p):
        print(f"rej{i}={','.join(sorted(o.name for o in pat.early_reject)) or '-'}")
    pf = T.get_transcendental_patterns(NON, True).patterns
    for i, (pat, f) in enumerate(pf):
        print(f"rejf{i}={','.join(sorted(o.name for o in pat.early_reject)) or '-'}")
    # the four rewrites the NON table holds, on the real op nodes
    d32 = dfp(dtypes.f32)
    d16 = dfp(dtypes.f16, "h")
    d64 = dfp(dtypes.f64, "g")
    for nm, u in (("f32_exp2", UOp(Ops.EXP2, src=(d32,))), ("f32_log2", UOp(Ops.LOG2, src=(d32,))),
                  ("f32_sin", UOp(Ops.SIN, src=(d32,))), ("f32_sqrt", UOp(Ops.SQRT, src=(d32,)))):
        rows("rw_" + nm, p[0][0] and u and T.get_transcendental_patterns(NON, False).rewrite(u))
    for nm, u in (("h16_exp2", UOp(Ops.EXP2, src=(d16,))), ("h16_sin", UOp(Ops.SIN, src=(d16,)))):
        rows("rw_" + nm, T.get_transcendental_patterns(NON, False).rewrite(u))
    rows("rw_i32_sqrt", T.get_transcendental_patterns(NON, False).rewrite(
        UOp(Ops.SQRT, src=(UOp.variable("q", 0, 100, dtypes.i32),))))
    # and the FORCE table on a float64 SIN, the widest one
    rows("rw_f64_sin", T.get_transcendental_patterns(ALL, True).rewrite(UOp(Ops.SIN, src=(d64,))))


if __name__ == "__main__":
    main()
