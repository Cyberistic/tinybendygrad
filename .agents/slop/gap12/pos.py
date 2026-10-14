#!/usr/bin/env python3
"""GAP 2, the other half: does CPython's `UPat` MATCH the node each of the 35
POSITIVE `sr *` rows is driven on?

The gate asserts the two sides AGREE on 35 strings. That is not a branch proof:
it is a pair of spellings. This asks CPython directly, per row, so a row whose
node the pattern REJECTS is visible instead of agreeing anyway.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "gates"))

_spec = importlib.util.spec_from_file_location(
    "_wo", str(ROOT / "gates/wgsl_render_census-oracle.py"))
O = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(O)

RULES = O.SR_RULES
# THE POSITIVE ROWS, read off `g_string_rewrite` (oracle:615-654) by NAME -- the
# node each one drives is re-built here through the SAME helpers, so this is
# the oracle's population, not a second transcription of it.
import tinygrad.uop.spec as spec                                     # noqa: E402
_spec2 = spec  # silence linters


def build():
    """`[(rowname, rule_index, node, ctx)]` -- one entry per positive `sr` row."""
    from tinygrad import dtypes
    from tinygrad.uop.ops import Ops, UOp
    ci = UOp.const(1, dtypes.int32)
    ch = UOp.const(1, dtypes.half)
    cu = UOp.const(1, dtypes.uint32)
    alt = UOp.const(7, dtypes.uint32)
    gate = UOp.const(1, dtypes.bool)
    vf = UOp.const(5, dtypes.float)
    idx_pk = UOp(Ops.INDEX, src=(O.buf_of("uint8", "AGlobal", 16), O._wc(1)))
    idx_pl = UOp(Ops.INDEX, src=(O.buf_of("single", "AGlobal", 16), O._wc(1)))
    cu3 = UOp.const(3, dtypes.uint32)
    rmw = O.packed_store(UOp.store(idx_pk, UOp.const(5, dtypes.uint8)))
    and_n = rmw.src[1].src[0]
    ix_n = and_n.src[0].src[0].src[0]
    wmask, newv = and_n.src[1], rmw.src[1].src[1]
    add = UOp(Ops.ADD, src=(O._wc(1), O._wc(2)), arg=Ops.ADD)
    iconst = O._wc(1)
    r = []
    r.append(("idx packed", 0, UOp(Ops.CAST, src=(idx_pk,), arg=dtypes.uint32), {idx_pk: "B[1]"}))
    r.append(("idx plain", 0, UOp(Ops.CAST, src=(idx_pl,), arg=dtypes.uint32), {idx_pl: "B[1]"}))
    r.append(("neg", 1, UOp(Ops.NEG, src=(cu3,)), {cu3: "X"}))
    r.append(("cbool 1", 2, UOp.cconst(1, dtypes.bool), {}))
    r.append(("cbool 0", 2, UOp.cconst(0, dtypes.bool), {}))
    for nm, hi, lo in O.SR_CU:
        r.append((f"cuchar {nm}", 3, O._cvar(O._i64(hi, lo)), {}))
    for nm, hi, lo in O.SR_CI:
        r.append((f"ci32 {nm}", 4, O._cint(O._i64(hi, lo)), {}))
    for nm, bn, ctor, a, k in O.SR_BUF:
        u = O.buf_of(ctor, a, k)
        r.append((f"buffer {nm}", 5, u, {u: bn}))
    r.append(("bhalf", 6, UOp(Ops.BITCAST, src=(cu,), arg=dtypes.half), {cu: "S"}))
    r.append(("buchar", 7, UOp(Ops.BITCAST, src=(ci,), arg=dtypes.uint8), {ci: "S"}))
    r.append(("bchar", 8, UOp(Ops.BITCAST, src=(ci,), arg=dtypes.char), {ci: "S"}))
    r.append(("bushort", 9, UOp(Ops.BITCAST, src=(ci,), arg=dtypes.uint16), {ci: "S"}))
    r.append(("bushort half", 9, UOp(Ops.BITCAST, src=(ch,), arg=dtypes.uint16), {ch: "S"}))
    r.append(("bshort", 10, UOp(Ops.BITCAST, src=(ci,), arg=dtypes.short), {ci: "S"}))
    r.append(("bshort half", 10, UOp(Ops.BITCAST, src=(ch,), arg=dtypes.short), {ch: "S"}))
    r.append(("bany", 11, UOp(Ops.BITCAST, src=(ch,), arg=dtypes.float), {ch: "S"}))
    r.append(("lgate packed", 12, UOp(Ops.LOAD, src=(idx_pk, alt, gate)),
              {idx_pk: "B[1]", alt: "V", gate: "G"}))
    r.append(("lgate plain", 12, UOp(Ops.LOAD, src=(idx_pl, alt, gate)),
              {idx_pl: "B[1]", alt: "V", gate: "G"}))
    r.append(("load packed", 13, UOp(Ops.LOAD, src=(idx_pk,)), {idx_pk: "B[1]"}))
    r.append(("load plain", 13, UOp(Ops.LOAD, src=(idx_pl,)), {idx_pl: "B[1]"}))
    r.append(("rmw nv", 14, rmw, {ix_n: "B[1]", wmask: "W", newv: "NV"}))
    r.append(("rmw bare", 14, UOp.store(ix_n, and_n), {ix_n: "B[1]", wmask: "W"}))
    r.append(("rmw plain", 14, UOp.store(idx_pl, vf), {idx_pl: "B", vf: "V"}))
    r.append(("store", 15, UOp.store(idx_pl, vf), {idx_pl: "B", vf: "V"}))
    r.append(("index add", 16, UOp(Ops.INDEX, src=(idx_pl, add)), {idx_pl: "B", add: "(I0+I1)"}))
    r.append(("index const", 16, UOp(Ops.INDEX, src=(idx_pl, iconst)), {idx_pl: "B", iconst: "I0"}))
    r.append(("index unbalanced", 16, UOp(Ops.INDEX, src=(idx_pl, add)),
              {idx_pl: "B", add: "(I0)+(I1)"}))
    return r


rows = build()
print(f"{len(rows)} positive sr rows (the gate's ROWS count is 207 overall)\n")
unmatched = []
for nm, i, u, ctx in rows:
    m = RULES[i][0].match(u, {})
    verdict = "MATCH" if m else "*** PATTERN REJECTS THE ROW'S OWN NODE ***"
    if not m:
        unmatched.append((nm, i))
    print(f"rule {i:>2}  {nm:<18} {verdict}")

print(f"\npositive rows whose node the pattern REJECTS: {len(unmatched)}"
      f" {unmatched if unmatched else ''}")