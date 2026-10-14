#!/usr/bin/env python3
"""GAP 2 MEASUREMENT: for each of wgsl.py's 17 `string_rewrite` rules, find a
node CPython's own `UPat` REJECTS, and report CPython's answer.

Nothing here is assumed. The rejection is asked of `PatternMatcher`, which is
the same object `_sr_rewrite` drives, so a row here and a row in the oracle
cannot disagree.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "gates"))

from tinygrad import dtypes                                     # noqa: E402
from tinygrad.uop.ops import Ops, UOp                           # noqa: E402
from tinygrad.uop.upat import PatternMatcher                     # noqa: E402
from tinygrad.renderer.wgsl import WGSLRenderer, base_rewrite   # noqa: E402
from tinygrad.helpers import strip_parens                        # noqa: E402

RULES = WGSLRenderer.string_rewrite.patterns[:17]      # (UPat, fn) PAIRS
PATS = [p for p, _f in RULES]
print("rules:", len(RULES))


def cst(v, dt=None):
    return UOp.const(v, dt) if dt is not None else UOp(Ops.CONST, arg=v, src=())


def rew(i, u, ctx=None):
    """THE SAME CALL the oracle's `_sr_rewrite` makes -- one rule, `rewrite`."""
    v = PatternMatcher([RULES[i]]).rewrite(u, ctx=ctx if ctx is not None else {})
    return "NOMATCH" if v is None else str(v)


import importlib.util                                            # noqa: E402
_spec = importlib.util.spec_from_file_location(
    "_wo", str(ROOT / "gates/wgsl_render_census-oracle.py"))
_WO = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_WO)
buf_of = _WO.buf_of                                              # the oracle's OWN


# --- the axis: ONE rejected node per rule -------------------------------
cu3 = cst(3)
ci = cst(1, dtypes.int32)
idx = UOp(Ops.INDEX, src=(buf_of("uint8", "AGlobal", 16), cst(1)))

CAND = [
    # 0 CAST->uint32 of an INDEX
    (0, "cast i32", UOp(Ops.CAST, src=(idx,), arg=dtypes.int32), {}),
    # 1 NEG of a FLOAT const: the pattern wants dtypes.uints
    (1, "neg f32", UOp(Ops.NEG, src=(cst(1, dtypes.float),)), {}),
    # 2 cvar cast to INT32, not bool
    (2, "cast i32", UOp.cconst(1, dtypes.int32), {}),
    # 3 cvar cast to INT32, not uchar/ushort/uint32
    (3, "cast i32", UOp(Ops.CAST, src=(cu3,), arg=dtypes.int32), {}),
    # 4 cvar cast to UINT32, not int32
    (4, "cast u32", UOp(Ops.CAST, src=(cu3,), arg=dtypes.uint32), {}),
    # 5 not a BUFFER
    (5, "const", cu3, {}),
    # 6 BITCAST to u32, not half
    (6, "bitcast u32", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.uint32), {}),
    # 7 BITCAST to half, not uchar
    (7, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
    # 8 BITCAST to uchar, not char
    (8, "bitcast uchar", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.uchar), {}),
    # 9 BITCAST to half, not ushort
    (9, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
    # 10 BITCAST to half, not short
    (10, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
    # 11 `UPat(Ops.BITCAST, name="x")` takes EVERY bitcast -- so the rejected
    #    node has to be a different OP
    (11, "const", cu3, {}),
    # 12 `UPat.load(b, v, gate)` wants THREE srcs; a two-src LOAD is rule 13's
    (12, "load 2", UOp(Ops.LOAD, src=(idx,)), {idx: "B[1]"}),
    # 13 `UPat.load(b)` -- does a three-src LOAD still match it?
    (13, "load 3", UOp(Ops.LOAD, src=(idx, cu3, cst(1, dtypes.bool))),
     {idx: "B[1]", cu3: "V"}),
    # 14 a packed store whose value is NOT packed_rmw
    (14, "store u8", UOp.store(idx, cst(5, dtypes.uint8)), {idx: "B[1]"}),
    # 15 a STORE with a GATE is three srcs
    (15, "store 3", UOp.store(idx, cu3, cst(1, dtypes.bool)), {idx: "B", cu3: "V"}),
    # 16 not an INDEX
    (16, "const", cu3, {}),
]

print(f"{'rule':>4} {'fixture':<12} {'CPython':<34} rejected?")
for i, nm, u, ctx in CAND:
    m = PATS[i].match(u, {})
    ans = rew(i, u, ctx)
    print(f"{i:>4} {nm:<12} {ans[:33]:<34} {'REJECTED' if not m else 'MATCHED **'}")