#!/usr/bin/env python3
"""rng_graph_census-oracle.py -- CPython's OP SEQUENCE for every (table, node) pair of
`rangeify.py`, driven through the REAL `PatternMatcher.rewrite`.

    .venv/bin/python gates/rng_graph_census-oracle.py

THE ORACLE CALLS THE REAL THING. `pm_const_buffer_folding.rewrite(uop)`, `pm_remove_bufferize
.rewrite(uop)`, ... are the objects `rangeify.py` builds at module scope and hands to
`graph_rewrite` in `get_kernel_graph` (rangeify.py:349-376). `PatternMatcher.rewrite` IS the
engine's per-node dispatch (ops.py:1613-1619) and the port's ten `*_rewrite` defs are its
mirror. Nothing here re-implements a fold, a claim test or a rule body.

THE ROW SET IS DISCOVERED, NOT LISTED. A ROW is a (TABLE, NODE) pair. TABLE ranges over
`rangeify.py`'s rule tables and NODE over the fixture, and BOTH sets are walked, so the
matrix is COMPLETE: a pair where the table does not fire prints `none`, and a pair where
CPython raises prints `raise=<ExcName>`. Both are answers, and dropping them would hide the
two failures a census exists to find -- a rule that fires where CPython does not, and a rule
whose body CPython cannot run at all.

`gs` IS IN THE WALK AND CONTRIBUTS NO ROW, which is a MEASUREMENT rather than an exclusion:
`gate_substitute` raises `BottomUpGate` (rangeify.py:44) on an empty ctx and
`graph_rewrite` catches that at ops.py:1835 and reads it as "no rewrite", so the engine's
answer on every node is "no rewrite" -- which is exactly the port's `gs_0` returning
`Hop{ar, 0}`. The ctx is passed as `{}` and the raise is caught BECAUSE the engine catches
it; that is the engine's own control flow, not a reimplementation of the rule.

THE FIXTURE IS THE PORT'S, MIRRORED, WITH ONE LEGALITY REPAIR. `rangeify.bend`'s `g()` builds
66 nodes in ONE arena (rangeify.bend:1710-1865) and :1868-1949 names each index; this lane
rebuilds the same 66 nodes with the same ops, srcs, tags and index order, so index `n` is the
same node on both sides. STAGE nodes are the ONE repair and it is a CPython invariant, not a
convenience: `remove_bufferize` reads `buf.arg.removable` (rangeify.py:54) and
`cleanup_dead_axes` reads `b.arg.removable` (:23), so a STAGE whose arg is `None` CRASHES the
real matcher -- MEASURED, `AttributeError: 'NoneType' object has no attribute 'removable'`.
Every STAGE in a real rangeified graph carries `BufferizeOpts` (`indexing.py:57-60`), so this
lane gives them `BufferizeOpts(device=None)`. The PORT cannot: `ops.bend`'s `Arg` has no
`BufferizeOpts` arm, which is the wall `rangeify.bend:2686` records. That asymmetry is why
`rb` and `ct` answer here and refuse there, and it is DECLARED, not smoothed.

THE SIGNATURE IS `Rng.sig` PLUS AN ARG AND A TAG. `Rng.sig` (ops.bend:5897) prints
`toposort_len Ops.ROOT/nsrc src_ops...` and NO arg -- and for THIS file the arg and the tag
are half the meaning: `pm_add_param_range_tags` exists to set a TAG, `renumber_range` to
rewrite a RANGE's arg, `pm_no_views` to hand back an EXISTING node. So ` arg=<ctor>` and
` t=<tag>` are appended, using the port's own `sg.ctor` / `sg.tag` vocabulary
(ops.bend:7540,7534) so the lanes agree on names rather than on a spelling chosen here.
"""

import itertools

from tinygrad.dtype import dtypes, AddrSpace, Invalid, DType
from tinygrad.uop.ops import UOp, Ops, ParamArg, KernelInfo, AxisType
from tinygrad.uop.ops import BottomUpGate
from tinygrad.schedule.indexing import BufferizeOpts
from tinygrad.schedule import rangeify as RF


def seq(u, seen=None, out=None):
    if seen is None:
        seen, out = set(), []
    if id(u) in seen:
        return out
    seen.add(id(u))
    for s in u.src:
        seq(s, seen, out)
    out.append(u.op.name)
    return out


def ctor(a) -> str:
    """`sg.ctor` -- ops.bend:7540, the ARG CONSTRUCTOR's name. `Invalid` is an INSTANCE of
    `InvalidType`, not a class (`tinygrad/dtype.py`), so it is tested by identity."""
    if a is None:
        return "none"
    if a is Invalid:
        return "cinvalid"
    if isinstance(a, DType):
        return "dt:" + a.name
    if isinstance(a, bool):
        return "cbool:" + str(a)
    if isinstance(a, int):
        return "cint"
    if isinstance(a, float):
        return "cfloat"
    return "other"


def tagnm(t) -> str:
    """`sg.tag` -- ops.bend:7534. `()` and `None` are DISTINCT (ops.py:244)."""
    if t is None:
        return "none"
    if isinstance(t, tuple):
        return "tuple"
    return str(t)


def sig(u) -> str:
    s = seq(u)
    srcs = " ".join("Ops." + x.op.name for x in u.src)
    return f"{len(s)} Ops.{u.op.name}/{len(u.src)} {srcs} arg={ctor(u.arg)} t={tagnm(u.tag)}"


def ps(slot, n, addr=AddrSpace.GLOBAL, dev=None):
    """`ParamArg(slot, dtype, size, ...)` with `size` a SCALAR `prod(shape)` (ops.py:1200)
    -- `UOp._shape` returns `(self.arg.size,)` (ops.py:369-371), so a TUPLE size would give
    `((n,),)` and a STAGE over it a shape of `(n, (n,))`, which is not a shape CPython can
    reshape through. The port's `g_psize` (`rangeify.bend:1688`) holds `Some{n}` -- the scalar.
    """
    return ParamArg(slot, dtypes.int32, n, addrspace=addr, device=dev)


def stage(*src):
    """A STAGE carrying CPython's mandatory `BufferizeOpts` -- `indexing.py:57-60`."""
    return UOp(Ops.STAGE, src=src, arg=BufferizeOpts(device=None))


def world():
    """THE PORT'S FIXTURE, node for node -- rangeify.bend:1710-1865, index for index."""
    c0, c1, c2, c4 = (UOp.const(v) for v in (0, 1, 2, 4))
    sp = UOp.special(4, "0")
    b4 = UOp(Ops.BUFFER, src=(sp,), arg=ps(0, 4))
    bx = UOp(Ops.BUFFER, src=(sp,), arg=ps(1, 4))
    r0, r1 = UOp.range(4, (0,), AxisType.WEAK), UOp.range(4, (1,), AxisType.WEAK)
    n0, nx = UOp(Ops.NOOP), UOp(Ops.NOOP, src=(c0,))
    e0, e1, ek = UOp(Ops.END, src=(n0,)), UOp(Ops.END, src=(nx,)), UOp(Ops.END, src=(b4,))
    af1 = UOp(Ops.AFTER, src=(b4, e0))
    af = UOp(Ops.AFTER, src=(b4, e0, e1, ek))
    afk = UOp(Ops.AFTER, src=(b4, ek))
    st2, st3 = stage(b4, r0), stage(b4, r0, r1)
    ixs = UOp(Ops.INDEX, src=(st2, r0))
    ixc = UOp(Ops.INDEX, src=(c4, r0))
    rs = UOp(Ops.RESHAPE, src=(b4, c4))
    rsi = UOp(Ops.RESHAPE, src=(ixs, c4))
    sh0 = UOp(Ops.SHRINK, src=(b4, c0, c4))
    sh1 = UOp(Ops.SHRINK, src=(b4, c1, c2))
    cst = UOp(Ops.CONST, src=(), arg=Invalid)
    mst = UOp(Ops.MSTACK, src=(sh1, sh0))
    cli = UOp(Ops.CALL, src=(ixs, rs))
    cls = UOp(Ops.CALL, src=(sh1, c0))
    clm = UOp(Ops.CALL, src=(mst, c0))
    msr = UOp(Ops.MSTACK, src=(rs, rs))
    sti = UOp(Ops.STORE, src=(b4, cst))
    sts = UOp(Ops.STORE, src=(b4, b4))
    std = UOp(Ops.STORE, src=(b4, bx))
    pg = UOp(Ops.PARAM, src=(), arg=ps(2, 4))
    pa = UOp(Ops.PARAM, src=(), arg=ps(3, 4, AddrSpace.ALU))
    ipg = UOp(Ops.INDEX, src=(pg,))
    ipa = UOp(Ops.INDEX, src=(pa,))
    r0t, pgt, pat = r0.rtag(()), pg.rtag(()), pa.rtag(())
    aftn = UOp(Ops.AFTER, src=(n0, e0))
    aftk = UOp(Ops.AFTER, src=(b4, ek))
    stc0 = UOp(Ops.STORE, src=(b4, c0))
    rsaf = UOp(Ops.RESHAPE, src=(af, c4))
    clik = UOp(Ops.CALL, src=(ixs, rs), arg=KernelInfo())
    clik0 = UOp(Ops.CALL, src=(ixs, rs))
    bd = UOp(Ops.BUFFER, src=(sp,), arg=ps(4, 9, dev="1:0"))
    ixb4 = UOp(Ops.INDEX, src=(b4, r0))
    ct4a, ct4d = stage(ixb4, r0), stage(ixb4, r1)
    ct4b = UOp(Ops.INDEX, src=(st2, r0))
    ct5k0 = UOp(Ops.CAST, src=(c4,), arg=dtypes.half)
    ct5c, ct5k, ct5b = stage(c4, r0), stage(ct5k0, r0), stage(b4, r0)
    mstc = UOp(Ops.MSTACK, src=(c4, c1))
    mstb = UOp(Ops.MSTACK, src=(bd, c1))
    ct8d = UOp(Ops.INDEX, src=(mstc,))
    ct8b = UOp(Ops.INDEX, src=(mstb,))
    ct8r = UOp(Ops.INDEX, src=(mstc, r0), arg=(AxisType.LOOP, (7,)))
    ct8r0 = UOp(Ops.INDEX, src=(mstc, r0))
    ct7a = UOp(Ops.INDEX, src=(af,))
    ct7b = UOp(Ops.INDEX, src=(r0, af))
    rgd = UOp.range(4, (2,), AxisType.DEVICE)
    rgt = rgd.rtag(())
    return [c0, c1, c2, c4, sp, b4, bx, r0, r1, n0, nx, e0, e1, ek, af1, af, afk,
            st2, st3, ixs, ixc, rs, rsi, sh0, sh1, cst, mst, cli, cls, clm, msr, sti,
            sts, std, pg, pa, ipg, ipa, r0t, pgt, pat, aftn, aftk, stc0, rsaf, clik,
            clik0, bd, ixb4, ct4a, ct4d, ct4b, ct5k0, ct5c, ct5k, ct5b, mstc, mstb,
            ct8d, ct8b, ct8r, ct8r0, ct7a, ct7b, rgd, rgt]


# THE TABLES, in the port's OWN table order -- `rb_table` .. `ab_table` are the port's
# tables 1..11 and `gs_table` is table 6. Discovered, not listed: every module-scope
# `PatternMatcher` in `rangeify.py` plus the two named matchers it calls
# (`to_define_global`, `split_kernels`) plus the `pm_mops` / `pm_flatten_range`
# compositions, which arrive inside `pm_const_buffer_folding` and `pm_add_buffers`.
def tables():
    # IN THE PORT'S OWN TABLE ORDER -- `rangeify.bend` numbers its tables 1..11 by the line of
    # `rangeify.py` each ports: rb=1 (:129) nic=2 (:158) nv=3 (:163) aprt=4 (:328) sk=5 (:344)
    # gs=6 (:45) ct=7 (:113) fb=8 (:242) dg=9 (:309) lb=10 (:196) ab=11 (:252). The gate diffs
    # the lanes LINE BY LINE, so the ORDER is part of the contract, and it is the PORT's order
    # read off the file rather than a second one chosen here.
    return [("rb", RF.pm_remove_bufferize, {}), ("nic", RF.pm_no_indexing_calls, {}),
            ("nv", RF.pm_no_views, {}), ("aprt", RF.pm_add_param_range_tags, {}),
            ("sk", RF.split_kernels, {}), ("gs", RF.pm_gate_substitute, {}),
            ("ct", RF.pm_const_buffer_folding, {}), ("fb", RF.pm_flatten_bufferize, {}),
            ("dg", RF.to_define_global, RF.LocalAddBufferContext()),
            ("lb", RF.pm_limit_bufs, RF.LimitBufsContext(range_idx=itertools.count(0))),
            ("ab", RF.pm_add_buffers, itertools.count(0))]


def drive(pm, ctx, u):
    """`rewrite`, with the engine's OWN two excusions: `BottomUpGate` (ops.py:1835) is
    'no rewrite', anything else is an answer CPython could not give."""
    try:
        r = pm.rewrite(u, ctx)
    except BottomUpGate:
        return None
    except Exception as e:
        return f"raise={type(e).__name__}"
    return None if r is None or r is u else sig(r)


if __name__ == "__main__":
    nodes = world()
    # EVERY ONE OF THE 726 PAIRS IS EMITTED, refusals included, so the two lanes carry the same
    # row count BY CONSTRUCTION and no exclusion list is needed to make the counts meet -- a lane
    # that filtered its own refusals would let a disagreement about WHICH pairs fire hide inside
    # the filter. The refusal token is the literal `none`, the same literal the port's `hsig`
    # returns, so a refusal is a byte-identical row and a divergence is a line a reader can see.
    for tag, pm, ctx in tables():
        for n, u in enumerate(nodes):
            print(f"{tag}_{n}={drive(pm, ctx, u) or 'none'}")