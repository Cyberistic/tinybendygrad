#!/usr/bin/env python3
"""f2f-arena-oracle.py -- CPython's INTERNING ORDER for the `f2f` fixtures, slot for
slot, which is the quantity `f2f-arena.bend` prints on the port side.

WHY THIS FILE EXISTS. The nine forward edges are a STRUCTURAL claim about the arena:
a node whose src is a later slot. A `sig=`/`k=` row is a CONE and a toposort, and a
toposort CANNOT show a forward edge -- it renumbers. So the port's `sig` can be a strict
prefix of CPython's and the port still be wrong; the arena order is the only lane that
sees it, and both sides have to be in it.

THE ORDER HOOK IS `dd-oracle.py`'s (`UOpMetaClass.__call__`, lines 77-91), reinstalled
here rather than reinvented: it records a node the FIRST time its key misses `ucache`,
which is exactly "interned into a fresh slot". CPython's index into `ORDER` is therefore
the same integer as the port's arena slot, because the port's arena is appended in the
same call order and `UOp.of` reads back the interned slot on a hit.

THE PRINT DECISIONS are `f2f-fixtures.py`'s (`uncast`/`cval`/`fbits`/`lab`), verbatim, so
the lane that RENDERS is shared and a disagreement is about the GRAPH.

⚠ `uncast` is needed on CPython's side too: `mixin/elementwise.py` inserts promotion
CASTs that dtype.py never writes, and a slot that disagrees only by an inserted CAST is a
FIXTURE disagreement, not a port bug. Both sides strip them.

THE FORWARD CHECK is here as well as on the port, from the SAME predicate and with the
same self-edge exclusion, so `0 FORWARD` on both sides is a statement about two graphs
rather than about two predicates. CPython's `ORDER` is dense and 0-based, so the
self-edge at slot 0 is the arena bottom exactly as `Arena.node`'s out-of-range answer is.
"""
import struct
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.codegen.decomp import dtype as DD

PROMO = set()
_CAST = type(UOp.variable("p", 0, 0)).cast


def _cast(self, dtype):
    r = _CAST(self, dtype)
    try:
        caller = sys._getframe(1).f_code.co_name
    except Exception:
        caller = '?'
    if caller in ('promote', 'logical_not') and r.op is Ops.CAST and r is not self:
        PROMO.add(id(r))
    return r


type(UOp.variable("p", 0, 0)).cast = _cast

ORDER = []
_CALL = UOpMetaClass.__call__


def _call(cls, op, src=(), arg=None, tag=None, metadata=None):
    key = (op, src, arg, tag, type(arg))
    fresh = key not in UOpMetaClass.ucache
    r = _CALL(cls, op, src, arg, metadata) if False else _CALL(cls, op, src, arg, tag, metadata)
    if fresh:
        ORDER.append(r)
    return r


UOpMetaClass.__call__ = _call


def uncast(v):
    while v.op is Ops.CAST and id(v) in PROMO:
        v = v.src[0]
    return v


def cval(a):
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
    return f"F({struct.unpack('I', struct.pack('f', float(x)))[0]})"


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        if isinstance(v.arg, bool):
            return f"C({int(v.arg)})"
        if isinstance(v.arg, int):
            return cval(v.arg)
        return fbits(v.arg)
    if v.op is Ops.PARAM:
        return f"P{v.arg.name}"
    return v.op.name


def f2f_dt_of(fr):
    return getattr(dtypes, f"uint{fr.bitsize}")


FIX = (("q1", dtypes.fp8e4m3, dtypes.float32),
       ("q2", dtypes.float32, dtypes.fp8e4m3),
       ("q3", dtypes.float32, dtypes.fp8e5m2),
       ("q4", dtypes.fp8e4m3fnuz, dtypes.float32),
       ("q5", dtypes.float32, dtypes.fp8e5m2fnuz),
       ("q7", dtypes.float32, dtypes.float64))


def fwd1(i, src):
    """THE IMPOSSIBLE EDGE IS `i <= src`, and a SELF-edge is excluded by `i != 0`.

    `is_lt(src, i)` -- the shape the predecessor used -- is TRUE for every well-formed
    edge, so it fires on every row including `0 NOOP <- 0,0`. That is a flag which reads
    as a clean bill of health while measuring nothing.
    """
    return i != 0 and (i < src or i == src)


def dump(nm, ans, base):
    """SLOTS ARE ABSOLUTE, not relative to the fixture.

    `ORDER` also holds the nodes the module-level fixture setup interned, and a node
    `f2f` wants may ALREADY be there -- `2**tm` is interned by `q1` and wanted again by
    `q3`. Printing relative slots and renumbering would put CPython's and the port's
    arenas in different numberings, and the forward check on a renumbered list is
    meaningless.
    """
    root = uncast(ans)
    slot = {id(u): i for i, u in enumerate(ORDER)}
    print(f"# {nm} root={slot[id(root)]} next={len(ORDER)} base={base}")
    for i in range(base, len(ORDER)):
        u = ORDER[i]
        src = [slot[id(uncast(s))] for s in uncast(u).src]
        fw = "FORWARD" if any(fwd1(i, s) for s in src) else ""
        print(f"{i}\t{u.op.name}/{len(u.src)}\t{lab(u)}\t<- " + ",".join(map(str, src)) +
              f"\t{fw}\t{'ROOT' if u is root else ''}")


def main():
    for nm, fr, to in FIX:
        base = len(ORDER)
        v = UOp.variable(nm, 0, 0, f2f_dt_of(fr))
        ans = DD.f2f(v, fr, to)
        dump(nm, ans, base)


if __name__ == "__main__":
    main()
