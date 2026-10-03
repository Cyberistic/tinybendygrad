#!/usr/bin/env python3
"""dd-cone-probe.py -- CALL CPython and dump the cone of the `l2i const sources`
fixtures (lgv/lgw/lgx) node by node, WITH arena identity and parent count, so the
bend fix is written against a measurement and not against a comment.

It LOADS dd-oracle.py as a module (hyphenated name, so importlib) so that the
PROMO marking, `uncast` and the interning-order hook are the oracle's own code
rather than a reimplementation of them.
"""
import importlib.util
import sys

sys.path.insert(0, '.')
spec = importlib.util.spec_from_file_location("dd_oracle", ".agents/slop/dd-oracle.py")
O = importlib.util.module_from_spec(spec)
spec.loader.exec_module(O)

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import dtype as DD


def probe(nm, dt, src):
    b = len(O.ORDER)
    r = DD.l2i(Ops.CAST, dt, src)
    roots = list(r)
    seen, out, parents = set(), [], {}

    def note(u):
        parents[id(u)] = parents.get(id(u), 0) + 1

    def go(v):
        v = O.uncast(v)
        if id(v) in seen:
            return
        seen.add(id(v))
        out.append(v)
        for s in v.src:
            note(O.uncast(s))
            go(s)

    for root in roots:
        note(O.uncast(root))
        go(root)

    print(f"{nm}: roots={[O.tree(x) for x in roots]}")
    print(f"  built this call (n): {len(O.kept(O.ORDER[b:]))}")
    print(f"  cone ({len(out)} nodes, oracle order):")
    for i, v in enumerate(out):
        n = parents.get(id(v), 0)
        print(f"    {i}: {v.op.name}/{len(v.src)}  incoming={n}  tree={O.tree(v)}")
    print(f"  sig={O.esig(out)}")
    print(f"  k={O.ck(out)}")


for nm, dt, src in (
    ("lgv", dtypes.long, UOp.const(0, dtypes.uint32)),
    ("lgw", dtypes.ulong, UOp.const(0, dtypes.uint32)),
    ("lgx", dtypes.ulong, UOp.const(1, dtypes.uint32)),
):
    probe(nm, dt, src)