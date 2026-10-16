#!/usr/bin/env python3
"""decomp_graph_census-oracle.py -- CPython's answer for every row of
`gates/decomp_graph_census.bend`, taken from the REAL `tinygrad/codegen/decomp/`.

    .venv/bin/python gates/decomp_graph_census-oracle.py

THE ORACLE CALLS THE REAL THING. Every `lg*` row is `l2i(...)` -- the module-level
function of `tinygrad/codegen/decomp/dtype.py:21` -- on a fixture that MIRRORS the port's
`l2i.pick` arm (`dtype.bend:2780-2834`) index for index: same op, same target dtype, same
source dtype, same word count, same offset into the same 24-node pool. `up` is the real
`unpack32` (:13). `c*` is the real `f2f_clamp` (:127). `q*` is the real `f2f` (:101).
`nrules_*` are `len()` of the REAL `get_simplifying_rewrite_patterns` /
`get_late_rewrite_patterns` dispatch tables of `tinygrad/codegen/decomp/op.py:66,81`.

Nothing here reimplements `l2i`, `f2f`, `f2f_clamp`, `unpack32`, or a rewrite rule body.
The `tn_bitwise_not` post-mortem in `gates/tn_bitwise_not-oracle.py` is the reason: an
oracle that hand-builds `cast.ne(true_)` instead of calling `Tensor.bitwise_not()` agrees
with a port that is ITSELF wrong, because both mint the CAST CPython folds.

THE CONE IS DFS PRE-ORDER, DEDUPED BY IDENTITY, ROOTED AT THE ANSWER'S WORD(S).
`l2i` answers a TUPLE for the arms dtype.py writes as a tuple and ONE `UOp` for the four
arms that answer a single word (dtype.py:39 `case Ops.CAST`, and CMPLT/CMPEQ/CMPNE), and
the port knows which is which without asking (`dtype.bend:2698`: "`hi == 0` IS 'ONE
NODE'"). This lane asks `isinstance(r, tuple)` and gets the same answer from CPython.

THE FIXTURE POOL IS THE PORT'S, MIRRORED: four `w` words (u8,u16,u32,u64) and then five
each of i32, u32, bool and f32 -- `dtype.bend:2549-2597`'s `dd_wpool` -- as SCALAR ALU
PARAMs. `size=None` is `ParamArg`'s own "None for scalars" (`ops.py:28`), which is what
the port's `size=Some{0}` denotes; a finite size makes `const_like` mint an EXPAND and
every cone grows a node the port's has no name for.

DOCUMENTED DIVERGENCE, PINNED NOT SMOOTHED: CPython inserts PROMOTION CASTs that the port does
not build -- `ElementwiseMixin._broadcasted`'s inner `promote` (mixin/elementwise.py:24-32),
`out_dtype = least_upper_dtype(x.dtype, y.dtype)` at :26 and `return promote(x), promote(y)`
over `t.cast(out_dtype)` at :32. MEASURED, this file used to attribute them to "`UOp.__init__`'s
`dtype_from_uop` and `_broadcasted`'s bool->int": `UOp` has no `__init__` (it is built by
`UOpMetaClass.__call__`, ops.py:197), `dtype_from_uop` (ops.py:122) returns a DType and mints no
node, and `UOp` has no `_broadcasted` -- the only one is `UPat._broadcasted` (ops.py:1534), a
pure reorder. This lane therefore prints CPython's cone AS BUILT, promotion casts included. Where
that makes the row differ the gate says so and says why; it does not erase nodes to manufacture
agreement.

WHAT THE CONE CANNOT SEE, NAMED BECAUSE IT IS THE THING THAT BIT THIS LANE. A CONST's
VALUE and DTYPE are in no node shape: `sig` prints `CONST/0` for every constant whatever it
holds. MEASURED on `q1`, whose row is byte-identical on both sides while the two constants
disagree: CPython's cone carries `CONST(True)` at index 17 and this lane's partner reads
`C(1)`, and CPython carries a weakfloat `127.0` at index 14 AND a weakint `127` at index 21
where the port's arena holds ONE `C(127)` and serves both roles. A wrong constant at the
right arity is invisible here by construction, and that is exactly the hole the
`f2f_dt[fr]` fixture fell into before the note above was written.
"""

from tinygrad.dtype import DType, dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg, AddrSpace
from tinygrad.codegen.decomp import dtype as DT

# ---------------------------------------------------------------- the 24-node pool
# dtype.bend:2549-2597 -- four `w` words then five each of i32, u32, bool, f32.
POOL = [dtypes.uint8, dtypes.uint16, dtypes.uint32, dtypes.uint64]
for _ in range(5): POOL.append(dtypes.int32)
for _ in range(5): POOL.append(dtypes.uint32)
for _ in range(5): POOL.append(dtypes.bool)
for _ in range(5): POOL.append(dtypes.float32)
# NAMED, or the pool HASH-CONSES TO ONE NODE. MEASURED: with an unnamed `ParamArg(0,dt,None,
# addrspace=ALU)` every same-dtype word is the SAME `UOp`, so `l2i(Ops.CMPNE, ..., 4 words)`
# sees one node four times and its cone reads `OR/2,CMPNE/2,PARAM/0` where the port's reads
# `OR/2,CMPNE/2,PARAM/0,PARAM/0,CMPNE/2,PARAM/0,PARAM/0`. The port names each word --
# `dd_pool.go` (:2513) appends the index to the name -- and THAT is the fixture.
PAR = [UOp(Ops.PARAM, src=(), arg=ParamArg(0, dt, None, name="%s%d" % (chr(119 + (i < 4)), i),
                                            addrspace=AddrSpace.ALU, device=None))
       for i, dt in enumerate(POOL)]


def ws(base, nw):
    return PAR[base:base + nw]


def s1(u):
    """`OP/NSRC`, AND `OP/NSRC[TARGET]` WHEN THE ARG IS A DTYPE.

    A CAST and a BITCAST are the two ops whose `arg` is a DType (ops.py:640 `cast`,
    ops.py:846 `bitcast`), and the test is on the ARG and not on the op, so a third op that
    ever grows one is printed by this and not by a second list that would rot beside it.

    `u.arg.name` IS the port's spelling, not a translation: MEASURED on this checkout
    `dtypes.uint8.name == "u8"`, `dtypes.float32.name == "f32"`, `dtypes.half.name == "f16"`,
    `dtypes.bfloat16.name == "bf16"` and `dtypes.fp8e4m3.name == "fp8e4m3"`, which is what
    `LAWS/spec.bend`'s `Dt.nm` holds (`spec.bend:727-742`) and what `O.dt_name` (ops.bend:5956)
    returns. So the two sides render the same token with no table on either.
    """
    if isinstance(u.arg, DType):
        return "%s/%d[%s]" % (u.op.name, len(u.src), u.arg.name)
    return "%s/%d" % (u.op.name, len(u.src))


def cone(roots):
    """DFS PRE-ORDER over every root, each node ONCE, parent before child."""
    out, seen = [], set()

    def go(v):
        if id(v) in seen:
            return
        seen.add(id(v))
        out.append(v)
        for s in v.src:
            go(s)
    for r in roots:
        go(r)
    return out


def sig(r):
    roots = list(r) if isinstance(r, tuple) else [r]
    return ",".join(s1(u) for u in cone(roots))


def drive(fn, *a, **kw):
    """One refusal TOKEN for both sides, and the TOKEN NAMES A REASON."""
    try:
        r = fn(*a, **kw)
    except NotImplementedError:
        return "raise=NotImplementedError"
    except Exception as e:  # noqa: BLE001 -- a raise IS the answer, and its name is the fact
        return "raise=%s" % type(e).__name__
    return None if r is None else sig(r)


# ------------------------------------------------------------- the `l2i` fixtures
# dtype.bend:2780-2834 `l2i.pick`, arms 0..32, index for index. The port names them
# lg1..lgy; this lane uses the SAME names so a row is one fact on both sides.
L2I = [
    ("lg1",  Ops.NEG, dtypes.int32, dtypes.uint32, 9, 2),
    ("lg2",  Ops.CAST, dtypes.int64, dtypes.int32, 4, 2),
    ("lg3",  Ops.CAST, dtypes.int64, dtypes.uint32, 9, 2),
    ("lg4",  Ops.CAST, dtypes.int64, dtypes.bool, 14, 2),
    ("lg5",  Ops.CAST, dtypes.int64, dtypes.float32, 19, 2),
    ("lg6",  Ops.CAST, dtypes.uint64, dtypes.int32, 4, 2),
    ("lg7",  Ops.CAST, dtypes.int32, dtypes.uint32, 9, 2),
    ("lg8",  Ops.BITCAST, dtypes.int64, dtypes.uint32, 9, 2),
    ("lg9",  Ops.SHL, dtypes.int32, dtypes.uint32, 9, 3),
    ("lga",  Ops.SHR, dtypes.int32, dtypes.uint32, 9, 3),
    ("lgb",  Ops.SHR, dtypes.uint32, dtypes.uint32, 9, 3),
    ("lgc",  Ops.ADD, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgd",  Ops.SUB, dtypes.int32, dtypes.uint32, 9, 4),
    ("lge",  Ops.MUL, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgf",  Ops.CMPLT, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgg",  Ops.CMPEQ, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgh",  Ops.CMPNE, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgi",  Ops.XOR, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgj",  Ops.OR, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgk",  Ops.AND, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgl",  Ops.WHERE, dtypes.int32, dtypes.uint32, 9, 5),
    ("lgm",  Ops.MAX, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgn",  Ops.FLOORDIV, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgo",  Ops.CAST, dtypes.int64, dtypes.uint32, 9, 1),
    ("lgq",  Ops.CDIV, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgr",  Ops.CMOD, dtypes.int32, dtypes.uint32, 9, 4),
    ("lgs",  Ops.CDIV, dtypes.uint32, dtypes.uint32, 9, 4),
    ("lgt",  Ops.CMOD, dtypes.uint32, dtypes.uint32, 9, 4),
    ("lgu",  Ops.CAST, dtypes.float32, dtypes.float32, 19, 2),
    ("lgy",  Ops.CAST, dtypes.int32, dtypes.int32, 4, 2),
]

for _nm, _op, _dt, _xdt, _base, _nw in L2I:
    print("%s=%s" % (_nm, drive(DT.l2i, _op, _dt, *ws(_base, _nw))))

# `l2i.const`'s THREE arms -- `l2i.pick`'s cases 28/29/30 (dtype.bend:2812, :2816, :2817),
# `l2i(Ops.CAST, dt, UOp.const(v, xdt))`. The argument is minted OUTSIDE the call, at `xdt`, so
# it reads NO word of the pool and no pool-based population rule can see these three; they are
# `uq`'s idea again from the other side, a CONST already AT the source dtype.
#
# `UOp.const` (ops.py:634) is `UOp(CONST, arg=dt.const(b)).cast(dt)`, so on this checkout it is
# itself a CAST -- MEASURED, printed above as `arg op=CAST dtype=u32` -- and the port's mirror of
# that half is `dd_const.int` (dtype.bend:333). Both sides therefore carry the argument's own
# `CAST/1[u32]`, and `lgw` is the row where CPython's `uops[0].cast(l2i_dt[dt])` FOLDS on top of
# it (`mixin/dtype.py:36`, `l2i_dt[ulong] == dtypes.uint`) while `lgx` is the ORDER-SENSITIVE
# NEIGHBOUR of `lgw`: the same two words, a different cone order.
for _nm, _v, _dt in (("lgv", 0, dtypes.int64), ("lgw", 0, dtypes.uint64),
                     ("lgx", 1, dtypes.uint64)):
    print("%s=%s" % (_nm, drive(DT.l2i, Ops.CAST, _dt, UOp.const(_v, dtypes.uint32))))

# `unpack32` (dtype.py:13) over the pool's u32 word at offset 9 -- dtype.bend:2850.
print("up=%s" % drive(DT.unpack32, PAR[9]))

# AND OVER THE POOL'S `i32` WORD AT OFFSET 4, which is the fixture that makes the BITCAST
# `ops.py:13` builds MINTED: `unpack32(u) = u.bitcast(types.uint32) & 0xFFFF, u.bitcast(
# types.uint32) >> 16` takes NO dtype and bitcasts unconditionally, so a `u32` receiver folds
# the node away and an `i32` receiver does not. MEASURED both: `PAR[9]` reads
# `AND/2,PARAM/0,CONST/0,FLOODIV/2,CONST/0` with no BITCAST and `PAR[4]` reads
# `AND/2,BITCAST/1[u32],PARAM/0,CONST/0,FLOODIV/2,CONST/0` with the ONE node shared by both
# halves. The port's `unpack32` takes the receiver's dtype as a parameter (`dtype.bend:591`,
# `O.eq_dt(xdt, S.uint32())`) to model that fold, so the two fixtures select the two graphs on
# both sides and the `u32` in the token is a TARGET THAT IS NOT THE SOURCE.
print("uq=%s" % drive(DT.unpack32, PAR[4]))

# `f2f` (dtype.py:101) over dtype.bend:3053-3061's seven pairs.
F2F = [("q1", dtypes.fp8e4m3, dtypes.float32), ("q2", dtypes.float32, dtypes.fp8e4m3),
       ("q3", dtypes.float32, dtypes.fp8e5m2), ("q4", dtypes.fp8e4m3fnuz, dtypes.float32),
       ("q5", dtypes.float32, dtypes.fp8e5m2fnuz), ("q6", dtypes.half, dtypes.bfloat16),
       ("q7", dtypes.float32, dtypes.float64)]

# THE FIXTURE IS `f2f_dt[fr]`, A UINT, AND NOT `fr` AND NOT `float32`. dtype.py:97 builds
# `f2f_dt` for exactly this and dtype.py:142 `f2f(val.bitcast(f2f_dt[to]), to, fr)` and
# dtype.py:197 `f2f(x.bitcast(f2f_dt[ctx[0]]), ctx[0], ctx[1])` BOTH pass it, so the
# narrowing arm's `v.bitcast(fr)` at dtype.py:116 is a REAL BITCAST that CPython builds and
# a PARAM already at `fr` would silently FOLD (`mixin/dtype.py:53`). MEASURED, all three
# fixtures over all seven rows:
#     at float32   3 rows agree (q4 q7 + the q6 refusal), q1 q2 q3 q5 differ
#     at fr        same three -- `fr` IS float32 for four of the seven, so it is the f32
#                  fixture under another name
#     at f2f_dt[fr] 4 agree (q1 q4 q7 + the refusal); q5 stops being its own shape and
#                  becomes a PROMOTION row like the ten `l2i` ones.
# The port's own `f2f.one` (dtype.bend:3043-3047) says the same and measures it: "passing
# `fr` here compiled, ran, and disagreed: ... the `fr` receiver costs `w1` a node (28
# against CPython's 27)".
#
# THIS LANE USED TO PASS `PAR[19]`, WHICH IS `float32` FOR EVERY ROW. THAT IS THE
# `tn_bitwise_not` POST-MORTEM AGAIN: the lane disagreed with the port on `q2 q3 q5`, the
# disagreement was declared a PORT FINDING ("one never-folding BITCAST"), and the BITCAST
# was the ORACLE's own -- it disappeared the moment the fixture was built at the dtype the
# two real call sites build it at. A FINDING THAT IS AN ARTEFACT OF THE ORACLE'S FIXTURE IS
# NOT A FINDING; `gates/tn_bitwise_not-oracle.py`'s docstring is the post-mortem and this
# sentence is the second occurrence.
def par(dt, name):
    return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dt, None, name=name,
                                                addrspace=AddrSpace.ALU, device=None))


for _nm, _fr, _to in F2F:
    print("%s=%s" % (_nm, drive(DT.f2f, par(DT.f2f_dt[_fr], _nm), _fr, _to, True)))