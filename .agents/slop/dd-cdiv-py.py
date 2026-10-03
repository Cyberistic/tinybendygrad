#!/usr/bin/env python3
"""dd-cdiv-py.py -- CPython's arena for ONE `l2i` fixture, slot by slot.

dtype.py's CDIV/CMOD loop interns 64 `UOp.const(i, dtypes.uint)` PAIRS (dtype.py:65),
so the port's cone is ~2500 nodes wide and a diff of two `sig` strings names none of
them. This dumps the CREATION ORDER with a slot index and a label, which is the same
fact the Bend arena holds, so the two can be compared position by position.

Every value here is MEASURED by calling tinygrad. Nothing is transcribed.

  dd-cdiv-py.py [op] [dt]      op in CDIV CMOD, dt in uint int; default CDIV uint
"""
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.codegen.decomp import dtype as DD

# dd-oracle.py's decisions, kept byte-identical so the two dumps are comparable:
# `mixin/elementwise.py`'s promotion CASTS are not ported, and decision 2's rendering.
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
    hi, lo = (v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF
    if hi == 0:
        return f"C({lo})"
    if hi == 0xFFFFFFFF:
        return f"C(-{0 if lo == 0 else 4294967296 - lo})"
    return f"C({hi}:{lo})"


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        return cval(v.arg) if isinstance(v.arg, int) and not isinstance(v.arg, bool) else f"C({int(v.arg)})"
    if v.op is Ops.PARAM:
        return f"P{v.arg.name}"
    return v.op.name


# THE FIXTURE SET, in dd-oracle.py's module order: WORD then WPOOL, so the session's
# interning state at the window boundary is the gate's.
F2F_DT = {f: getattr(dtypes, f"uint{f.bitsize}") for f in dtypes.floats}
WORD = {dt: UOp.variable("w", 0, 0, dt) for dt in F2F_DT.values()}
WPOOL = {dt: tuple(UOp.variable(f"{dt.name}{i}", 0, 0, dt) for i in range(5))
         for dt in (dtypes.i32, dtypes.u32, dtypes.bool, dtypes.f32)}

op = Ops[sys.argv[1] if len(sys.argv) > 1 else "CDIV"]
dt = {"uint": dtypes.uint, "int": dtypes.int}[sys.argv[2] if len(sys.argv) > 2 else "uint"]

# THE WHOLE L2I TABLE IN ORDER, not one row: the rows share one interning session and
# `UOp.const(i, dtypes.uint)` is interned by the first row that needs it, so running
# one row alone reports an arena the gate never sees.
want = sys.argv[3] if len(sys.argv) > 3 else None
TABLE = [("lg1", Ops.NEG, dtypes.int, dtypes.u32, 2),
         ("lg2", Ops.CAST, dtypes.long, dtypes.i32, 2),
         ("lg3", Ops.CAST, dtypes.long, dtypes.u32, 2),
         ("lg4", Ops.CAST, dtypes.long, dtypes.bool, 2),
         ("lg5", Ops.CAST, dtypes.long, dtypes.f32, 2),
         ("lg6", Ops.CAST, dtypes.ulong, dtypes.i32, 2),
         ("lg7", Ops.CAST, dtypes.int, dtypes.u32, 2),
         ("lg8", Ops.BITCAST, dtypes.long, dtypes.u32, 2),
         ("lg9", Ops.SHL, dtypes.int, dtypes.u32, 3),
         ("lga", Ops.SHR, dtypes.int, dtypes.u32, 3),
         ("lgb", Ops.SHR, dtypes.uint, dtypes.u32, 3),
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
         ("lgn", Ops.FLOORDIV, dtypes.int, dtypes.u32, 4),
         ("lgo", Ops.CAST, dtypes.long, dtypes.u32, 1),
         ("lgq", Ops.CDIV, dtypes.int, dtypes.u32, 4),
         ("lgr", Ops.CMOD, dtypes.int, dtypes.u32, 4),
         ("lgs", Ops.CDIV, dtypes.uint, dtypes.u32, 4),
         ("lgt", Ops.CMOD, dtypes.uint, dtypes.u32, 4)]
b = 0
for nm, o, d, xd, n in TABLE:
    b = len(ORDER)
    try:
        out = DD.l2i(o, d, *list(WPOOL[xd][:n]))
    except Exception:
        continue
    if want is None or nm == want:
        w = len(ORDER) - b
        print(f"# {nm} from={b} to={len(ORDER)} n={w}")
        for i in range(w):
            u = ORDER[b + i]
            print(f"{b + i}={u.op.name}/{len(u.src)}\t{lab(u)}\t<- " +
                  ",".join(f"{s.op.name}:{lab(s)}" for s in u.src))