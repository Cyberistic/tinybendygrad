#!/usr/bin/env python3
# dd-oracle.py -- the ORACLE for tinybendygrad/codegen/decomp/dtype.bend.
#
# It calls CPython's tinygrad/codegen/decomp/dtype.py and prints what each
# function BUILDS, in the shape the Bend gate prints, so the two lanes are
# diffed row for row. Python is the reference; nothing here is a
# reimplementation of it. Every `py=` expectation in the gate is this file's
# output, copied verbatim.
#
# ---------------------------------------------------------------------------
# THE PRINT-SHAPE DECISIONS, all measured, none of them a reimplementation.
#
# 1. `mixin/elementwise.py` IS NOT PORTED, so the CASTs an operator overload
#    inserts that dtype.py never wrote are DELETED HERE AND ONLY HERE. There are
#    exactly two such places and they are identified by the PYTHON FUNCTION that
#    called `.cast` (`sys._getframe(1).f_code.co_name`):
#      * `ElementwiseMixin._broadcasted`'s inner `promote`, which casts both
#        operands to their `least_upper_dtype` -- every `a + b`, `a & b`,
#        `a == b`, `a < b` and `a.where(x, y)` goes through it;
#      * `ElementwiseMixin.logical_not`'s `self.cast(dtypes.bool)`, which is what
#        `a >= b`, `a != b` and `a == b` all end in.
#    dtype.py's OWN `.cast(...)` calls are KEPT, and two of them are load-bearing
#    (`.bitcast(dtypes.uint).cast(cdt)` and `.cast(dt)` at dtype.py:38 reinterpret
#    bits as a float). `op.bend`'s oracle deletes EVERY non-identity CAST and
#    cannot be reused here for exactly that reason. The marker comes from the
#    caller's frame, so it cannot mark a CAST dtype.py wrote.
#
# 2. A CONST prints as its ARENA WORD, which is what `ops.bend` stores. An integer
#    CONST prints as `C(<hi>:<lo>)` when the 64-bit word has a non-zero high
#    word, and `C(<lo>)` when it does not; a negative 32-bit CONST prints as
#    `C(-<mag>)`. A float CONST prints as `F(<its 32 bits>)`, NOT as a decimal:
#    `H.f32_show` spells a non-integral value with six decimals and prints an
#    integer-valued one through `U32.show`, which is out of range above 2**32 --
#    so a decimal could not agree with the port at `float32` max. The bit
#    pattern agrees exactly and `fc*`/`c*` compare it.
#    `mxc*` compares the F32 bits of `f2f_clamp`'s `mx`, which is `mx` after
#    `float32` rounding for every source width the gate uses.
#
# 3. `*sig` is the arena's CREATION ORDER -- `op/nsrc` for every node interned
#    while the fixture ran, in the order CPython interned them. It is recorded by
#    wrapping `UOpMetaClass.__call__` and checking whether the key was absent, so
#    it is CPython's own order and not a toposort this file performed. It is the
#    row that makes the DEEP structure observable: `tree*` only reaches two
#    levels.
# ---------------------------------------------------------------------------
import struct
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, DType
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass, GroupOp
from tinygrad.uop import GroupOp
from tinygrad.codegen.decomp import dtype as DD

# ---- decision 1: mark the CASTs `mixin/elementwise.py` inserts ----------------
PROMO = set()
_CAST = DTypeMixin_cast = type(UOp.variable("p", 0, 0)).cast


def _cast(self, dtype):
    r = _CAST(self, dtype)
    try:
        caller = sys._getframe(1).f_code.co_name
    except Exception:
        caller = '?'
    # `r is not self` IS THE POINT. `promote` calls `t.cast(out_dtype)` even
    # when `out_dtype == t.dtype`, and then `cast` returns `t` ITSELF -- so a
    # marker that does not exclude the fold marks whatever node `t` happened to
    # be. Measured: that marked `l2i`'s own `lo = uops[0].cast(l2i_dt[dt])` and
    # the oracle printed `lg5=Pf320` for a node that IS `CAST(f32_0, i32)`.
    if caller in ('promote', 'logical_not') and r.op is Ops.CAST and r is not self:
        PROMO.add(id(r))
    return r


type(UOp.variable("p", 0, 0)).cast = _cast

# ---- decision 3: CPython's own interning order --------------------------------
ORDER = []
_CALL = UOpMetaClass.__call__


def _call(cls, op, src=(), arg=None, tag=None, metadata=None):
    key = (op, src, arg, tag, type(arg))
    fresh = key not in UOpMetaClass.ucache
    r = _CALL(cls, op, src, arg, tag, metadata)
    if fresh:
        ORDER.append(r)
    return r


UOpMetaClass.__call__ = _call

L2I_DT = {dtypes.long: dtypes.int, dtypes.ulong: dtypes.uint}
F2F_DT = {f: getattr(dtypes, f"uint{f.bitsize}") for f in dtypes.floats}


def uncast(v):
    while v.op is Ops.CAST and id(v) in PROMO:
        v = v.src[0]
    return v


def cval(a):
    """decision 2: an integer CONST as its 64-bit arena word."""
    v = int(a)
    hi = (v >> 32) & 0xFFFFFFFF
    lo = v & 0xFFFFFFFF
    if hi == 0:
        return f"C({lo})"
    if hi == 0xFFFFFFFF:
        mag = 0 if lo == 0 else 4294967296 - lo
        return f"C(-{mag})"
    return f"C({hi}:{lo})"


def fbits(x):
    """decision 2: a float CONST as its F32 bit pattern. `numpy`-free overflow
    guard: `struct.pack('f', ...)` RAISES above the f32 range, and that IS the
    answer for a `float64` target, so it prints as `F(ovf)` and the port prints
    nothing for that fixture (divergence E)."""
    try:
        return f"F({struct.unpack('I', struct.pack('f', float(x)))[0]})"
    except OverflowError:
        return "F(ovf)"


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        return cval(v.arg) if isinstance(v.arg, int) and not isinstance(v.arg, bool) \
            else fbits(v.arg) if isinstance(v.arg, float) else f"C({int(v.arg)})"
    if v.op is Ops.PARAM: return f"P{v.arg.name}"
    return v.op.name


def sh1(v):
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(lab(s) for s in v.src)})"


def tree(v):
    if v is None: return "none"
    v = uncast(v)
    if not v.src: return lab(v)
    return f"{lab(v)}({','.join(sh1(s) for s in v.src)})"


def kept(built):
    """the nodes the PORT builds. `mixin/elementwise.py` is not ported, so the
    two CAST kinds decision 1 deletes are missing from the Bend arena and must
    be missing from the inventory too -- they are real CPython nodes and the
    count would otherwise disagree on every row with an operator in it."""
    return [u for u in built if id(u) not in PROMO]


def sig(built):
    return ",".join(f"{u.op.name}/{len(u.src)}" for u in kept(built))


def csig(built):
    """the CONSTANTS created, in order -- `sig` alone cannot separate two
    `f2f_clamp`s whose graphs are the same SHAPE over different `mx` values,
    because `lab` prints a CAST as the bare word `CAST`."""
    return ",".join(lab(u) for u in kept(built) if u.op is Ops.CONST) or "-"


def run(nm, body):
    """run one fixture, print the four facts plus the answer, capture the creation order"""
    b = len(ORDER)
    try:
        out = body()
    except Exception as e:
        print(f"{nm}=refused:{type(e).__name__}")
        print(f"{nm}n={len(kept(ORDER[b:]))}")
        print(f"{nm}sig={sig(ORDER[b:])}")
        return None
    print(f"{nm}={tree(out)}")
    print(f"{nm}n={len(kept(ORDER[b:]))}")
    print(f"{nm}sig={sig(ORDER[b:])}")
    print(f"{nm}k={csig(ORDER[b:])}")
    return out


# THE FIXTURE NODES ARE BUILT ONCE, BEFORE ANY MEASUREMENT, because they are
# INTERNED: the first fixture that asks for a CONST finds the one an earlier
# fixture already made, and a per-fixture `UOp.variable` would move every row's
# `sig` for no reason.
#
# FIVE words per dtype, because `l2i`'s WHERE arm reads `uops[4]` and a
# four-word pool makes that an IndexError -- measured, and it is why the
# five-word fixture exists. `xdt` is the dtype of `uops[0]`, so a fixture varies
# the ARM IT LANDS ON by varying the pool, not by passing a flag: CPython reads
# the dtype off the node and the port is handed the same value as `xdt`.
WORD = {dt: UOp.variable("w", 0, 0, dt) for dt in F2F_DT.values()}
WPOOL = {dt: tuple(UOp.variable(f"{dt.name}{i}", 0, 0, dt) for i in range(5))
         for dt in (dtypes.i32, dtypes.u32, dtypes.bool, dtypes.f32)}


def P(dt):
    return WORD[dt]


def words(xdt):
    return WPOOL[xdt]


def ws(xdt, n):
    return list(WPOOL[xdt][:n])


# (name, op, dt, xdt, nwords) -- the `l2i` table. `xdt` is the dtype of uops[0],
# which Python reads off the node and the port is handed; it is the ONLY dtype of
# a UOp that `l2i` ever reads. NOT uniform: `l2i`'s CDIV loop is 64 iterations of
# one shape and an all-equal fixture would not tell a reversal from the identity.
def L2I():
    return [
        ("lg1", Ops.NEG, dtypes.int, dtypes.u32, 2),
        ("lg2", Ops.CAST, dtypes.long, dtypes.i32, 2),      # sign extend
        ("lg3", Ops.CAST, dtypes.long, dtypes.u32, 2),      # zero extend
        ("lg4", Ops.CAST, dtypes.long, dtypes.bool, 2),     # bool zero extends
        ("lg5", Ops.CAST, dtypes.long, dtypes.f32, 2),      # the float-source arm
        ("lg6", Ops.CAST, dtypes.ulong, dtypes.i32, 2),
        ("lg7", Ops.CAST, dtypes.int, dtypes.u32, 2),       # plain bitcast+cast, ONE node
        ("lg8", Ops.BITCAST, dtypes.long, dtypes.u32, 2),
        ("lg9", Ops.SHL, dtypes.int, dtypes.u32, 3),
        ("lga", Ops.SHR, dtypes.int, dtypes.u32, 3),        # fill = sign
        ("lgb", Ops.SHR, dtypes.uint, dtypes.u32, 3),       # fill = zero
        ("lgc", Ops.ADD, dtypes.int, dtypes.u32, 4),
        ("lgd", Ops.SUB, dtypes.int, dtypes.u32, 4),
        ("lge", Ops.MUL, dtypes.int, dtypes.u32, 4),
        ("lgf", Ops.CMPLT, dtypes.int, dtypes.u32, 4),
        ("lgg", Ops.CMPEQ, dtypes.int, dtypes.u32, 4),
        ("lgh", Ops.CMPNE, dtypes.int, dtypes.u32, 4),
        ("lgi", Ops.XOR, dtypes.int, dtypes.u32, 4),
        ("lgj", Ops.OR, dtypes.int, dtypes.u32, 4),
        ("lgk", Ops.AND, dtypes.int, dtypes.u32, 4),
        ("lgl", Ops.WHERE, dtypes.int, dtypes.u32, 5),
        ("lgm", Ops.MAX, dtypes.int, dtypes.u32, 4),
        ("lgn", Ops.FLOORDIV, dtypes.int, dtypes.u32, 4),   # the raise arm
        ("lgo", Ops.CAST, dtypes.long, dtypes.u32, 1),      # one word: the arity raise
        ("lgq", Ops.CDIV, dtypes.int, dtypes.u32, 4),
        ("lgr", Ops.CMOD, dtypes.int, dtypes.u32, 4),
        ("lgs", Ops.CDIV, dtypes.uint, dtypes.u32, 4),
        ("lgt", Ops.CMOD, dtypes.uint, dtypes.u32, 4),
    ]


# `f2f`. NOT uniform: fp8 SOURCES are in the widening branch only (divergence D
# records why), and the narrowing branch is f32/f64 sources against every
# narrower target.
def F2F():
    return [
        ("f1", dtypes.fp8e4m3, dtypes.f32),
        ("f2", dtypes.fp8e4m3fnuz, dtypes.f32),              # the fnuz widening arm
        ("f3", dtypes.fp8e5m2fnuz, dtypes.f32),
        ("f4", dtypes.fp8e4m3, dtypes.f64),                 # 2**32 and 2**52 CONSTs
        ("g1", dtypes.float, dtypes.half),
        ("g2", dtypes.float, dtypes.bfloat16),
        ("g3", dtypes.float, dtypes.fp8e4m3),
        ("g4", dtypes.float, dtypes.fp8e5m2),
        ("g5", dtypes.float, dtypes.fp8e4m3fnuz),           # the fnuz narrowing arm
        ("g6", dtypes.float, dtypes.fp8e5m2fnuz),
        ("g7", dtypes.float, dtypes.double),                # the widening branch
        ("h1", dtypes.double, dtypes.float),
        ("h2", dtypes.double, dtypes.half),
        ("h3", dtypes.double, dtypes.bfloat16),
        ("h4", dtypes.double, dtypes.fp8e4m3),
        ("k1", dtypes.float, dtypes.float),                 # neither branch: the raise
        ("k2", dtypes.fp8e4m3, dtypes.fp8e5m2),             # neither branch: the raise
        ("k3", dtypes.bfloat16, dtypes.half),               # neither branch: the raise
    ]


# `rne(v, s)` over a word of the source's unsigned width. `s = 42` makes the
# mask `2**41 - 1`, which no `U32` shift can name.
def RNE():
    return [("rn1", dtypes.float, 13), ("rn2", dtypes.float, 16), ("rn3", dtypes.double, 29),
            ("rn4", dtypes.double, 42), ("rn5", dtypes.float, 1), ("rn6", dtypes.float, 0)]


CLAMP_DTS = [dtypes.fp8e4m3, dtypes.fp8e4m3fnuz, dtypes.fp8e5m2, dtypes.fp8e5m2fnuz,
             dtypes.float16, dtypes.bfloat16, dtypes.float32, dtypes.float64]


def clamp_mx(dt):
    e, m = dtypes.finfo(dt)
    if dt in dtypes.fp8_fnuz: max_exp, max_man = (1 << e) - 1, (1 << m) - 1
    else: max_exp, max_man = ((1 << e) - 1, (1 << m) - 2) if dt == dtypes.fp8e4m3 else ((1 << e) - 2, (1 << m) - 1)
    return 2.0 ** (max_exp - DD.exponent_bias(dt)) * (1.0 + max_man / (1 << m))


def clamp_fr():
    return [("fc1", dtypes.float32, dtypes.fp8e4m3), ("fc2", dtypes.float32, dtypes.f16),
            ("fc3", dtypes.float32, dtypes.bfloat16), ("fc4", dtypes.float32, dtypes.fp8e4m3fnuz),
            ("fc5", dtypes.float32, dtypes.fp8e5m2fnuz), ("fc6", dtypes.float32, dtypes.float32),
            ("fc7", dtypes.float64, dtypes.f16), ("fc8", dtypes.float32, dtypes.fp8e5m2, False)]


def IDX():
    base = UOp.variable("t", 0, 0, dtypes.u32)
    zero = UOp.const(0, dtypes.u32)
    one = UOp.const(1, dtypes.u32)
    return [
        ("ri1", UOp(Ops.INDEX, src=(base, zero, one)), 0, 2),
        ("ri2", UOp(Ops.INDEX, src=(base, zero, one)), 5, 2),
        ("ri3", UOp(Ops.INDEX, src=(base, zero, one)), 5, 1),
        ("ri4", UOp(Ops.SHRINK, src=(base, zero, one)), 0, 2),
        ("ri5", UOp(Ops.SHRINK, src=(base, zero, one)), 7, 1),
        ("ri6", UOp(Ops.SHRINK, src=(base, zero, one)), 7, 2),
    ]


# `l2i_define` reads `x.addrspace`, so a `UOp.variable` (which is `ALU`) REFUSES
# every time -- measured. These are hand-built `ParamArg`s: a GLOBAL `long`, a
# GLOBAL `ulong`, a GLOBAL sized `long` for the `size*2` arm, and one ALU
# neighbour that must still refuse.
def defines():
    from tinygrad.uop.ops import ParamArg, AddrSpace
    def par(nm, dt, size=None, addr=AddrSpace.GLOBAL):
        return UOp(Ops.PARAM, arg=ParamArg(0, dt, size=size, name=nm, addrspace=addr))
    return [
        ("df1", par("v", dtypes.long, addr=AddrSpace.ALU)),   # the raise
        ("df2", par("g", dtypes.long)),                        # size None stays None
        ("df3", par("h", dtypes.ulong)),
        ("df4", par("i", dtypes.long, size=4)),                # size 4 -> 8
        ("df5", par("j", dtypes.f32)),                         # no l2i_dt entry: KeyError
    ]


def sizes(x):
    a = x.arg
    return f"{a.dtype.name}/{a.size}"


def main():
    print("# l2i_dt and f2f_dt")
    for i, (k, v) in enumerate(L2I_DT.items()):
        print(f"l2idt{i}={k.name}->{v.name}")
    for i, (k, v) in enumerate(F2F_DT.items()):
        print(f"f2fdt{i}={k.name}->{v.name}")
    print("f2fdt8=none")                      # an integer is not in dtypes.floats
    print(f"u32n={len(L2I()) + len(F2F()) + len(RNE()) + len(IDX()) + len(defines())}")
    print("# l2i")
    for nm, op, dt, xdt, n in L2I():
        w = ws(xdt, n)
        b = len(ORDER)
        try:
            r = DD.l2i(op, dt, *w)
        except Exception as e:
            print(f"{nm}=refused:{type(e).__name__}")
            print(f"{nm}n={len(kept(ORDER[b:]))}")
            print(f"{nm}sig={sig(ORDER[b:])}")
            continue
        if not isinstance(r, tuple): r = (r,)
        print(f"{nm}={tree(r[0])}")
        # SIX of dtype.py's seventeen `l2i` arms answer ONE node rather than a
        # pair -- `Ops.CAST`'s `else`, `CMPLT`, `CMPEQ`, `CMPNE` and
        # `return r if op is Ops.CMOD else q` -- so the second column exists only
        # for the arms that answer two, and the port's `hi == 0` says "one".
        if len(r) > 1:
            print(f"{nm}p={tree(r[1])}")
        print(f"{nm}n={len(kept(ORDER[b:]))}")
        print(f"{nm}sig={sig(ORDER[b:])}")
        print(f"{nm}k={csig(ORDER[b:])}")
    print("# unpack32")
    u = DD.unpack32(WPOOL[dtypes.u32][0])
    print(f"up0={tree(u[0])}")
    print(f"up1={tree(u[1])}")
    print("# reindex")
    for nm, idx, off, mul in IDX():
        run(nm, lambda: DD.reindex(idx, off, mul))
    print("# rne")
    for nm, fr, s in RNE():
        v = P(F2F_DT[fr])
        run(nm, lambda: DD.rne(v, s))
    # THE CLAMPS COME BEFORE `f2f`: `f2f` calls `f2f_clamp` internally, so a
    # clamp measured after them has already interned every node it would build
    # and reads `n=0` -- which is CPython's answer and a useless one here.
    for row in clamp_fr():
        nm, fr, to = row[0], row[1], row[2]
        sat = row[3] if len(row) > 3 else True
        # `f2f` reaches `f2f_clamp` through `v.bitcast(fr)`, and `const_like`
        # lands at THAT dtype -- a raw uint word would make `val.const_like(
        # float('inf'))` an `int(inf)` OverflowError, measured.
        v = P(F2F_DT[fr]).bitcast(fr)
        run(nm, lambda: DD.f2f_clamp(v, to, sat))
    print("# f2f")
    for nm, fr, to in F2F():
        v = P(F2F_DT[fr])
        run(nm, lambda: DD.f2f(v, fr, to))
    print("# f2f_clamp's mx value, and its graph")
    for i, dt in enumerate(CLAMP_DTS):
        print(f"c{i}={fbits(clamp_mx(dt))}")
    print("# l2i_define")
    for nm, x in defines():
        r = run(nm, lambda: DD.l2i_define(x))
        print(f"{nm}sz={sizes(uncast(r if r is not None else x))}")
    print("# the three tables: rule counts and reject-set sizes")
    for nm, pm in (("nlong", DD.pm_long_decomp), ("nfloat", DD.pm_float_decomp), ("ndtype", DD.pm_dtype_decomps)):
        print(f"{nm}={len(pm.patterns)}")
        for i, p in enumerate(pm.patterns):
            pat = p[0]
            print(f"{nm}{i}={len(pat.early_reject)}")
            print(f"{nm}{i}r={','.join(sorted(o.name for o in pat.early_reject)) or '-'}")
            print(f"{nm}{i}o={','.join(sorted({o.name for o in (pat.op or ())})) or '-'}")


if __name__ == "__main__":
    main()