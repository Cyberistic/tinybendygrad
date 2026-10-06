#!/usr/bin/env python3
# tx-arena.py -- the ORACLE for tinybendygrad/codegen/transcendental.bend.
#
# WHAT IT PRINTS. For each expansion, EVERY node tinygrad interned, in intern
# order, in a WINDOW. The arena is FRESH per expansion (`UOp.ucache.clear()`), so
# every window starts at 0 and every row is self-contained.
#
# THE TWO ERASURES, both MEASURED, and they are the only difference between
# Python's arena and the port's:
#   (a) PROMOTION CASTs -- `mixin/elementwise.py`'s `_broadcasted` calls `.cast()`
#       on a non-CONST. `ops.bend`'s `UOp.new` runs no promotion. Traced by
#       monkeypatching `_broadcasted`.
#   (b) `UOp.const`'s OWN FOLD -- ops.py:638 is
#       `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`, and the port's
#       `UOp.const` IS that fold: the port's `Const` carries the VALUE and a bare
#       CONST node has no dtype to promote into. Traced by monkeypatching
#       `UOp.const`. This is the ONE place a CONST's dtype is visible at all in
#       this file, and it is invisible in the port.
# EVERY OTHER CAST IS KEPT -- `rintk`'s output cast, `frexp`'s bitcasts,
# `cody_waite`'s `int64` round trip, `payne_hanek`'s `_shl_lazy`/`_shr_lazy` --
# because ops.bend can build one and keeping them pins twice as much. The
# shape-based rule decomp.bend's oracle uses (`arg != src.dtype`) is TOO COARSE
# here: it eats those explicit casts, merges two arena slots into one, and
# silently rewires every src index.
#
# AN ARENA HOLDS EACH KEY ONCE. The intern hook below can observe a duplicate
# (`UOp.ucache`'s VALUES are weakrefs and die, so a later `UOp.const(v)` can miss
# and re-create a node the fixture already had). `UOp.make.intern` in the port
# would not have created the second one, so the window DEDUPES BY KEY, FIRST
# WINS, and resolves every src BY KEY rather than by identity. That is the
# arena's own rule, restated.
#
# SLOT 0 IS THE PORT'S BOTTOM NOOP (`Arena.bottom()`), which Python's ucache does
# not have. Printing it is what lines the two windows up.
#
# ROW SHAPE:
#     n_<tag>=<nodes in the window>
#     a_<tag>=<idx>,<OP>,<arg>,<src>,<src>...
# CONST args print as cb0/cb1 (bool), cf<32bits> (float -- the port's CFloat is
# an F32), ci<hi:lo> (int, two words, because 2**62 has no U32 image).
import sys, struct
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.mixin.dtype import DTypeMixin
from tinygrad.mixin.elementwise import ElementwiseMixin
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.codegen.decomp import transcendental as T

INSIDE = [False]
PROMOTED = set()
FOLDED = set()
ARENA = []

_orig = UOpMetaClass.__call__


def hooked(cls, op, src=(), arg=None, tag=None, metadata=None):
    r = _orig(cls, op, src, arg, tag, metadata)
    if not any(r is a for a in ARENA): ARENA.append(r)
    return r


UOpMetaClass.__call__ = hooked

_cast = DTypeMixin.cast


def traced_cast(self, dt):
    before = self._uop
    r = _cast(self, dt)
    if INSIDE[0] and r is not before: PROMOTED.add(id(r))
    return r


DTypeMixin.cast = traced_cast

_bc = ElementwiseMixin._broadcasted


def traced_bc(self, y, reverse=False):
    INSIDE[0] = True
    try: return _bc(self, y, reverse)
    finally: INSIDE[0] = False


ElementwiseMixin._broadcasted = traced_bc

_uconst = UOp.const


def traced_const(b, dtype=None):
    r = _uconst(b, dtype)
    if r.op is Ops.CAST: FOLDED.add(id(r))
    return r


UOp.const = staticmethod(traced_const)


def canon(v):
    while v.op is Ops.CAST and (id(v) in PROMOTED or id(v) in FOLDED): v = v.src[0]
    return v


def key(v):
    # The key is STRUCTURAL, recursively. `id()` is not usable here:
    # `UOp.ucache`'s VALUES are weakrefs and they die, so the SAME node is
    # re-created later in the window with a fresh id and every key that mentions
    # it by id changes with it. `a_xsin 11` and `a_xsin 202` are both
    # `CMPNE(PARAM d, CONST inf)`; the second exists only because the first one's
    # weakref died, and `UOp.make.intern` in the port would not have made it.
    #
    # A CONST's key is its VALUE, not `repr(v.arg)`, and this is a THIRD erasure
    # rather than a fourth claim. `UOp.const(x)` with no dtype gives
    # `arg = ConstFloat(x)` while `UOp.const(x, dtypes.f32)` gives
    # `arg = dtypes.f32` -- the DTYPE object, whose repr is the dtype's name --
    # so the same float read as a bare Python literal and as `d.const_like(x)`
    # are TWO nodes in Python's arena. The port's `CFloat` carries the value and
    # nothing else (divergence B), so it has one. Keying a CONST on its bits
    # merges exactly those pairs and nothing else: `a_xsin 125` and `a_xsin 181`
    # are both `cf1070141403` and only the second is a real slot here.
    if v.op is Ops.CONST: return (v.op, cargs(v))
    return (v.op, tuple(key(canon(u)) for u in v.src), repr(v.arg), repr(v.tag))


def ci64(x):
    x &= (1 << 64) - 1
    return f"ci{x >> 32}:{x & 0xFFFFFFFF}"


def cargs(v):
    if v.op is Ops.CONST:
        x = v.arg
        if isinstance(x, bool): return f"cb{int(x)}"
        if isinstance(x, float): return f"cf{struct.unpack('<I', struct.pack('<f', x))[0]}"
        return ci64(int(x))
    if v.op is Ops.PARAM: return f"p{v.arg.name}"
    if v.op in (Ops.CAST, Ops.BITCAST): return v.arg.name
    return "-"


def kept_list():
    """The window's nodes: the two erasures applied, then FIRST-WINS by key.

    `a_<tag>=<i>` is `i + 1` for `kept[i]`, so slot 1 is the bottom NOOP. Both
    `dump` and the `sw` rows go through here, because a filter that only one of
    them applies makes the two disagree about what slot N is.
    """
    kept, keys = [], {}
    for v in ARENA:
        if v.op is Ops.CAST and (id(v) in PROMOTED or id(v) in FOLDED): continue
        k = key(v)
        if k in keys: continue
        keys[k] = len(kept) + 1; kept.append(v)
    return kept, keys


def dump(tag):
    kept, keys = kept_list()
    print(f"n_{tag}={len(kept) + 1}")
    print(f"a_{tag}=0,NOOP,-,-")
    for i, v in enumerate(kept):
        src = [str(keys[key(canon(u))]) for u in v.src]
        print(f"a_{tag}={i + 1},{v.op.name},{cargs(v)},{','.join(src) or '-'}")


def main():
    i32 = dtypes.i32
    for dt, dn in ((dtypes.f16, "f16"), (dtypes.f32, "f32"), (dtypes.f64, "f64")):
        print(f"mt_{dn}={T.mantissa_bits(dt)}")
        print(f"eb_{dn}={T.exponent_bias(dt)}")
        print(f"em_{dn}={T.exponent_mask(dt)}")
    items = [
        ("rintk", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.rintk(d)),
        ("pow2if", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.pow2if(q3, dtypes.f32)),
        ("ilogb", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.ilogb2k(d)),
        ("ldexp3", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.ldexp3k(d, qe2f)),
        ("ldexp2", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.ldexp2k(d, qe2)),
        ("frexp", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.frexp(d)),
        ("cw", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.cody_waite_reduction(d)),
        ("ph", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.payne_hanek_reduction(d)),
        ("sp", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.sin_poly(d)),
        ("sps", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.sin_poly_small(x, q1)),
        ("spl", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.sin_poly_large(x, q2)),
        ("xsinf", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.xsin(d, fast=True)),
        ("xsin", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.xsin(d)),
        ("xexp2", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.xexp2(d)),
        ("xlog2", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.xlog2(d)),
        ("xpow", lambda d, x, q3, qe2, qe2f, q1, q2, q2f: T.xpow(d, q2f)),
    ]

    def fresh():
        UOp.ucache.clear(); ARENA.clear(); PROMOTED.clear(); FOLDED.clear()
        return (UOp.variable("d", 0.0, 100.0, dtypes.f32),
                UOp.variable("x", -1.0, 1.0, dtypes.f32),
                UOp.const(3, i32), UOp.const(-2, i32), UOp.const(-2.0, dtypes.f32),
                UOp.const(1, i32), UOp.const(2, i32), UOp.const(2.0, dtypes.f32))

    for tag, f in items:
        dd, xx, a3, a2, a2f, a1, a2i, a2ff = fresh()
        f(dd, xx, a3, a2, a2f, a1, a2i, a2ff)
        dump(tag)
    # `xsin`'s `switch_over` is a PARAMETER (transcendental.py:170), so the row
    # reads the CONST that lands at the SAME SLOT for two different values. The
    # shape does not depend on it, which is what makes the pair discriminate: a
    # port that hard-coded 30.0 prints the same bits twice.
    for lbl, sw in (("sw30", 30.0), ("sw7", 7.0)):
        dd, xx, a3, a2, a2f, a1, a2i, a2ff = fresh()
        T.xsin(dd, fast=False, switch_over=sw)
        kept, keys = kept_list()
        print(f"{lbl}={cargs(kept[156]) if len(kept) > 156 else chr(45)}")

    # THE TABLE -- op.py:267-277. `ops` and `force` are PARAMETERS.
    NON = tuple(o for o in Ops if o not in (Ops.EXP2, Ops.LOG2, Ops.SIN))
    NOSQ = tuple(o for o in Ops if o is not Ops.SQRT)
    for lbl, pm in (("non", T.get_transcendental_patterns(NON, False)),
                    ("force", T.get_transcendental_patterns(NON, True)),
                    ("nosq", T.get_transcendental_patterns(NOSQ, False)),
                    ("empty", T.get_transcendental_patterns(tuple(), False)),
                    ("all", T.get_transcendental_patterns(tuple(Ops), False))):
        print(f"n_{lbl}={len(pm.patterns)}")
        for i, (p, fn) in enumerate(pm.patterns):
            ops = ",".join(o.name for o in p.op)
            rej = ",".join(sorted(o.name for o in p.early_reject)) or "-"
            md = ",".join(str(t).split(".")[-1] for t in p.match_dtype) if p.match_dtype else "-"
            nm = p.name or "-"
            print(f"e_{lbl}{i}={ops}|{rej}|{md}|{nm}")


if __name__ == "__main__":
    main()