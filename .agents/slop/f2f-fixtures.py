#!/usr/bin/env python3
"""f2f-fixtures.py -- CPython side of the three `f2f` fixtures, MINIMAL and CALLED.

`dd-bandoracle.py` builds `UOp.variable(nm, 0, dtypes.float).cast(fr)`, which mints a
`CAST` node the port's fixture does not have -- the port's is a bare `PARAM` of dtype `fr`
(`.agents/slop/dd-bandprobe.bend`). Comparing the two lanes then reports a disagreement
that is a FIXTURE difference, not a port bug, and the cone offset by one hides every
later disagreement behind it. So the input here is `UOp.variable(nm, 0, fr)` DIRECTLY,
which is dtype.py's own `f2f(v, fr, to)` contract: `v` is a node of dtype `fr` and
nothing in `f2f` reads anything else about it.

WHAT THIS FIXTURE SET REACHES, per dtype.py:
    w1  fp8e4m3 -> float32   widening, dtype.py:104 `fe <= te and fm < tm`
    n1  float32 -> fp8e4m3   narrowing, dtype.py:115, e4m3 target -> f2f.down.*
    n2  float32 -> fp8e5m2   narrowing, NON-e4m3 target, the only way into f2f.down.m2
    f1  fp8e4m3fnuz -> float32   the fnuz arm of `f2f.up`, dtype.py:108
    f2  float32 -> fp8e5m2fnuz   the fnuz arm of `f2f.down`, dtype.py:123
    x1  float16 -> bfloat16      dtype.py:125 `else: raise NotImplementedError`
    x2  float32 -> float64       the refusal whose `fe > te and fm == tm` half

⚠ `UOp.variable` is `variable(name, min_val, max_val, dtype=dtypes.weakint,
multiple_of=1)` (ops.py:1015), so **the dtype is the FOURTH argument**. The three-arg
form `UOp.variable(nm, 0, fr)` compiles, answers a PARAM, and gives a `weakint` -- and
`f2f`'s narrowing branch then REFUSES with `bitcast requires concrete dtypes, got
dtypes.weakint -> dtypes.f32` (dtype.py:116). That is a LIVE fixture bug in
`.agents/slop/dd-bandoracle.py:133`, which uses the three-arg form and therefore got its
`n1`/`n2` rows by way of the `v.cast(fr)` on the next line rather than by the fixture it
claims. The two CASTs that lane shows in `w1sig` (`CAST/1` at position 6) are that
workaround. Corrected here; `f2f`'s own contract is `v` is a node of dtype `fr`, which is
what the port's fixture builds too.
"""
import struct
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.codegen.decomp import dtype as DD

# `dd-bandoracle.py`'s print decisions, verbatim: drop the promotion CASTs
# `mixin/elementwise.py` inserts, render a CONST as its arena WORD and a float CONST as
# its F32 bit pattern. Borrowed so the lane that RENDERS is shared, which is what makes a
# disagreement about the GRAPH rather than about the printer.
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

# `dd-oracle.py`'s OWN interning-order hook (its lines 77-91), installed here rather than
# reinvented, so `window()` counts what that file counts.
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


def sh1(v):
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(lab(s) for s in v.src)})"


def tree(v):
    v = uncast(v)
    if not v.src:
        return lab(v)
    return f"{lab(v)}({','.join(sh1(s) for s in v.src)})"


def cone(roots):
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


def esig(built):
    return ",".join(f"{u.op.name}/{len(u.src)}" for u in built)


def eck(built):
    seen, out = set(), []

    def go(v):
        v = uncast(v)
        if id(v) in seen:
            return
        seen.add(id(v))
        if v.op is Ops.CONST:
            out.append(lab(v))
        for s in v.src:
            go(s)
    for r in built:
        go(r)
    return ",".join(out)


# ⚠⚠ THE RECEIVER'S DTYPE IS `f2f_dt[fr]`, NOT `fr`. BOTH REAL CALL SITES SAY SO, and
# this is the third fixture bug these rows have found:
#
#     dtype.py:142   f2f(val.bitcast(f2f_dt[to]), to, fr)     <- `f2f_store`
#     dtype.py:196   f2f(x.bitcast(f2f_dt[ctx[0]]), ctx[0], ctx[1])
#
# `f2f_dt[f] = getattr(dtypes, f"uint{f.bitsize}")` (dtype.py:97), so the receiver is a
# UINT of the source's width. A fixture that hands `f2f` a receiver of dtype `fr` takes a
# different path in `mixin/dtype.py:53`, whose `bitcast` is
# `return self if self.dtype == dt else ...` -- so with a `fr` receiver
# `v.bitcast(fr)` FOLDS to `v` and the BITCAST disappears, and the fixture measures a
# graph dtype.py never builds. MEASURED: `v.bitcast(f32) is v` is `True` for an `f32`
# receiver and `False` for a `u32` one. That is a fixture disagreement with the port that
# would have been read as a PORT BUG, and the port would have been "fixed" into building
# a node CPython does not have.
#
# So `f2f_dt[fr]` is computed here and the receiver carries it. `fr`/`to` -- the FLOAT pair
# that selects the branch -- are unchanged.
def f2f_dt_of(fr):
    return getattr(dtypes, f"uint{fr.bitsize}")


# ⚠ THE NAMES ARE `q*` AND NOT `f*`/`g*`/`h*`/`k*`, because `dd-oracle.py` ALREADY OWNS
# those for the SAME defs with DIFFERENT fixtures: its `f1` is `fp8e4m3 -> f32` where
# this file's `w1` was, its `f2` is `fp8e4m3fnuz -> f32` where this file's `f1` was, and
# its `g3`/`g4`/`g6`/`g7` are the three narrowing fixtures and the f64 widening one.
# Two DIFFERENT fixtures under one `name=` key is a disagreement manufactured by the
# naming, and `dd-band-diff.py` cannot see it -- it compares whole `name=value` lines and
# a collision looks exactly like a real bug. Measured: with `f1`/`f2` reused, the differ
# reported 8 disagreements of which 4 were this collision. The `q*` names are disjoint from
# every row `dd-oracle.py` prints (`grep -c '^q' dd-oracle.txt` is 0).
#
# `dd-oracle.py` COULD be diffed against for the `sig`/`k`/`=` facts, and its expectations
# are better in one respect: it interns a shared POOL first, so a CONST a later fixture
# wants is already there. Its `n=` is therefore a different WINDOW from a fresh arena's,
# which is why this file prints its own `n=`.

FIX = (("q1", dtypes.fp8e4m3, dtypes.float32),
       ("q2", dtypes.float32, dtypes.fp8e4m3),
       ("q3", dtypes.float32, dtypes.fp8e5m2),
       ("q4", dtypes.fp8e4m3fnuz, dtypes.float32),
       ("q5", dtypes.float32, dtypes.fp8e5m2fnuz),
       ("q6", dtypes.float16, dtypes.bfloat16),
       ("q7", dtypes.float32, dtypes.float64))


def window():
    """Nodes interned SINCE THE MARK, i.e. the port's `to - from`.

    `dd-oracle.py`'s own `ORDER` hook (`UOpMetaClass.__call__`) is installed here rather
    than reinvented: it records a node the first time its key misses the ucache, which is
    exactly "interned". The port's `rows.put` prints `O.Arena.next(ar) - from`, the number
    of arena slots the fixture added, so this is the same quantity. Printing the CONE
    size instead would compare two different facts -- the cone deduplicates shared
    subtrees and the window does not -- and `q1c` carries the cone separately so the two
    are never confused again. Measured on the corrected fixture: window 22, cone 27.
    """
    return len(ORDER)


def main():
    for nm, fr, to in FIX:
        v = UOp.variable(nm, 0, 0, f2f_dt_of(fr))
        b = window()
        try:
            ans = DD.f2f(v, fr, to)
        except NotImplementedError as e:
            # dtype.py:125 is the ONLY refusal `f2f` raises, and it names its own
            # condition. Printing the exception TYPE rather than the message, because the
            # message interpolates the two dtypes and the port's refusal is a tag.
            print(f"{nm}=refused:NotImplementedError")
            print(f"{nm}n={window() - b}")
            continue
        c = cone([ans])
        print(f"{nm}={tree(ans)}")
        # `n=` IS THE WINDOW, NOT THE CONE, and it must be the same quantity the port's
        # `rows.put` prints (`to - from`, the arena slots the fixture interned). Printing
        # `len(cone)` here compares two different facts: the cone is deduplicated across
        # shared subtrees and the window is not. Measured on the CORRECTED fixture:
        # port `q1n` 22, cone 27, window 22 -- the cone and the window differ by 5 and a
        # gate that mixes them is a gate that is always red for the wrong reason.
        print(f"{nm}n={window() - b}")
        print(f"{nm}c={len(c)}")
        print(f"{nm}sig={esig(c)}")
        print(f"{nm}k={eck(c)}")


if __name__ == "__main__":
    main()