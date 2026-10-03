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
    """decision 2: a float CONST as its F32 bit pattern.

    THE `except OverflowError: return "F(ovf)"` ARM THAT USED TO BE HERE IS DEAD,
    and its docstring was false. Measured on this interpreter (3.12.10, arm64
    macOS) over 2516 doubles -- `m * 2.0**e` for every `e` in -320..308 and
    `m` in {1.0, 1.5, 1.9999, 3.7}: **zero** raised. Every finite double above
    FLT_MAX packs to `+inf` (0x7f800000) and `struct.pack` says nothing:

        struct.pack('f', 1.7976931348623157e308)  ->  b'\\x00\\x00\\x80\\x7f'  (inf)
        struct.pack('f', 1e300)                   ->  b'\\x00\\x00\\x80\\x7f'  (inf)

    So `F(ovf)` was never a value, `dd-oracle.txt` could not have been produced
    by this script, and the old claim "f2f_clamp(f64_val, float64) -> 1.8e308
    -> F(ovf)" was wrong twice: `1.8e308` renders as `F(2139095040)`, and
    `+inf` renders as `F(2139095040)` too, so the two source widths COINCIDE
    here. That false claim had already propagated into
    `tinybendygrad/codegen/decomp/dtype.bend`'s comment; see the report."""
    return f"F({struct.unpack('I', struct.pack('f', float(x)))[0]})"


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


def cone(roots):
    """THE CANONICAL ROW. Every node REACHABLE from the answer root(s), each ONCE,
    in DFS pre-order: parent before child, src[0] before src[1].

    It is invariant to WHEN a node was interned -- arena slot numbers, the
    creation window and the order the body happened to call things never appear --
    and to SHARING, because `UOpMetaClass.ucache` interns structurally, so two
    equal nodes ARE one object and the walk visits an object once. That is the
    whole point: `dtype.py:22`'s `zero = UOp.const(0, dt)` is interned by the first
    fixture that needs it and reused by every later one, so a node inventory
    measured over the window is a property of the SESSION, not of `l2i`. Measured:
    this file's own `u32n` row calls `IDX()`, which interns `C(0)`/`C(1)` at u32
    before the first `l2i` fixture runs.

    It still cannot see: how many slots were minted (the `<nm>n=` row, which still
    measures interning); a node's dtype/tag/metadata; which src of a node an equal
    node is (the sharing it is blind to on purpose); and a raise that minted nodes
    before it fired -- CPython has no cone for a refusal and neither does the port.
    """
    seen, out = set(), []

    def go(v):
        v = uncast(v)
        if id(v) in seen:
            return
        seen.add(id(v))
        out.append(v)
        for s in v.src:
            go(s)
    for r in roots:
        go(r)
    return out


def esig(nodes):
    return ",".join(f"{u.op.name}/{len(u.src)}" for u in nodes)


def csig(built):
    """the CONSTANTS created, in order -- `sig` alone cannot separate two
    `f2f_clamp`s whose graphs are the same SHAPE over different `mx` values,
    because `lab` prints a CAST as the bare word `CAST`."""
    return ",".join(lab(u) for u in kept(built) if u.op is Ops.CONST) or "-"


def ck(nodes):
    """the cone's constants, in the cone's order. `op/nsrc` carries no VALUE, so
    a node's constant is invisible to `sig` without this."""
    return ",".join(lab(u) for u in nodes if u.op is Ops.CONST) or "-"


def roots_of(r):
    """`l2i` and `f2f_clamp` answer ONE UOp and `l2i`'s other arms answer a pair;
    `isinstance(r, tuple)` is CPython's own statement of which, and the port says
    the same thing with `hi == 0`."""
    return list(r) if isinstance(r, tuple) else [r]


def run(nm, body):
    """run one fixture, print the four facts plus the answer.

    A REFUSAL prints `refused:<ExceptionType>`, `n`, and nothing else: CPython
    has no answer, so it has no cone.  The port's `l2i` has exactly one refusal
    arm (dtype.py:81) and names it; the other families name theirs too.
    """
    b = len(ORDER)
    try:
        out = body()
    except Exception as e:
        print(f"{nm}=refused:{type(e).__name__}")
        print(f"{nm}n={len(kept(ORDER[b:]))}")
        return None
    c = cone(roots_of(out))
    print(f"{nm}={tree(out)}")
    print(f"{nm}n={len(kept(ORDER[b:]))}")
    print(f"{nm}sig={esig(c)}")
    print(f"{nm}k={ck(c)}")
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
        ("lgo", Ops.CAST, dtypes.long, dtypes.u32, 1),      # one word: CAST reads uops[0], does not raise
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


def clamp_mx(fr, dt, sat=True):
    """dtype.py:131's `mx`, CALLED, not transcribed.

    This USED to hand-copy dtype.py:128-131's arithmetic -- which contradicted
    this file's own header ("nothing here is a reimplementation of it") and was
    wrong twice over, because the value that reaches the graph is not the
    Python float. `val.const_like(b)` is `UOp.const(b, val.dtype)` (ops.py:601),
    so `mx` is a CONST AT THE SOURCE WIDTH `fr`, already rounded:

        f2f_clamp(f32_val, float64) -> mx = UOp.const(inf)
        f2f_clamp(f64_val, float64) -> mx = UOp.const(1.7976931348623157e+308)

    Read back out of CPython's OWN graph rather than recomputed. dtype.py:133
    returns `val.ne(val).where(val, (val < -mx).where(-sat, (mx < val).where(
    sat, val)))`, so `mx` is the `-mx` multiply's left operand at
    `r.src[2].src[0].src[1].src[0]` -- one uniform path for every dtype, and
    the arm is unconditional. `.val` there is the CAST's, i.e. the `fr`-rounded
    value, which is the thing `const_like` produced.

    MEASURED, all 8 dtypes x both `fr` -- `c0..c6` are byte-identical to the
    hand-transcribed formula and `c7` is `F(2139095040)` under BOTH `fr`
    (f32 gives `inf`, f64 gives 1.797e308, and `fbits` renders both as
    0x7f800000). So `c7` is not under-determined, it is CONSTANT: no fixture on
    the `fr` axis can move it. That is a blind spot with a reason, not a gap.
    """
    r = DD.f2f_clamp(UOp.variable("t", 0, 0, fr), dt, sat)
    return r.src[2].src[0].src[1].src[0]


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
            continue
        if not isinstance(r, tuple):
            r = (r,)
        print(f"{nm}={tree(r[0])}")
        # FOUR of dtype.py's seventeen `l2i` arms answer ONE node rather than a
        # pair -- `Ops.CAST`'s `else` at :39, CMPLT, CMPEQ and CMPNE -- so the
        # second column exists only for the arms that answer two, and the port's
        # `hi == 0` says "one".
        if len(r) > 1:
            print(f"{nm}p={tree(r[1])}")
        c = cone(list(r))
        print(f"{nm}n={len(kept(ORDER[b:]))}")
        print(f"{nm}sig={esig(c)}")
        print(f"{nm}k={ck(c)}")
    print("# unpack32")
    # `up=`/`upp=` rather than `up0=`/`up1=`: two-root answers use the port's
    # generic shape, which is the `l2i` one. `WPOOL[u32][0]` is pool word 9.
    ub = len(ORDER)
    u = DD.unpack32(WPOOL[dtypes.u32][0])
    print(f"up={tree(u[0])}")
    print(f"upp={tree(u[1])}")
    cu = cone([u[0], u[1]])
    print(f"upn={len(kept(ORDER[ub:]))}")
    print(f"upsig={esig(cu)}")
    print(f"upk={ck(cu)}")
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
    print("# l2i_define")
    for nm, x in defines():
        r = run(nm, lambda: DD.l2i_define(x))
        print(f"{nm}sz={sizes(uncast(r if r is not None else x))}")
    # Appended, not inserted: a const built here must not move an earlier row's
    # `n=`. `long` is `dtypes.i64` (tinygrad/dtype.py:142). The pair is `(lo, hi)`
    # from dtype.py:31 (`return lo, lo.const_like(0)`), and `.cast` folds only when
    # the dtypes already agree (mixin/dtype.py:36).
    print("# l2i const sources")
    for nm, dt, src in (
        ("lgv", dtypes.long, UOp.const(0, dtypes.uint32)),
        ("lgw", dtypes.ulong, UOp.const(0, dtypes.uint32)),
        ("lgx", dtypes.ulong, UOp.const(1, dtypes.uint32)),
    ):
        b = len(ORDER)
        r = DD.l2i(Ops.CAST, dt, src)
        print(f"{nm}={tree(r[0])}")
        print(f"{nm}p={tree(r[1])}")
        c = cone(list(r))
        print(f"{nm}n={len(kept(ORDER[b:]))}")
        print(f"{nm}sig={esig(c)}")
        print(f"{nm}k={ck(c)}")
    # dtype.py:35-38. Two f32 words, because the arm reads `a0` and `a1`. One word
    # is `UnboundLocalError`, not `NotImplementedError`, and not this arm.
    fa0, fa1 = WPOOL[dtypes.f32][:2]
    b = len(ORDER)
    fr = DD.l2i(Ops.CAST, dtypes.float32, fa0, fa1)
    print(f"lgu={tree(fr)}")
    cu = cone([fr])
    print(f"lgun={len(kept(ORDER[b:]))}")
    print(f"lgusig={esig(cu)}")
    print(f"lguk={ck(cu)}")
    print("# the three tables: rule counts and reject-set sizes")
    for nm, pm in (("nlong", DD.pm_long_decomp), ("nfloat", DD.pm_float_decomp), ("ndtype", DD.pm_dtype_decomps)):
        print(f"{nm}={len(pm.patterns)}")
        for i, p in enumerate(pm.patterns):
            pat = p[0]
            print(f"{nm}{i}={len(pat.early_reject)}")
            print(f"{nm}{i}r={','.join(sorted(o.name for o in pat.early_reject)) or '-'}")
            print(f"{nm}{i}o={','.join(sorted({o.name for o in (pat.op or ())})) or '-'}")
    # LAST, because `clamp_mx` CALLS `f2f_clamp` and therefore INTERNS nodes, and
    # `ORDER` counts a node only the FIRST time it is interned. Run anywhere else
    # and the CONSTs it builds stop counting for whichever fixture came after --
    # the same trap the "the clamps come before f2f" note above is about, one
    # level up. `fr` is PINNED to f32 because `fc1..fc6, fc8` all use it, and
    # `clamp_mx`'s docstring carries the measurement that f64 agrees on all 8.
    print("# f2f_clamp's mx value")
    for i, dt in enumerate(CLAMP_DTS):
        print(f"c{i}={fbits(clamp_mx(dtypes.float32, dt).val)}")


if __name__ == "__main__":
    main()