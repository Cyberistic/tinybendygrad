#!/usr/bin/env python3
r"""tn_nodes-gate.py -- EVERY NODE of `tn_isfinite`, against CPython, in toposort order.

    .venv/bin/python gates/tn_nodes-gate.py

FIFTEEN ROWS, THREE LANES, **ZERO DECLARED DIVERGENCES**. Every one of `tn_isfinite`'s
nodes is compared against tinygrad's `Tensor.isfinite`, one row per node, and the two
graphs agree node for node today.

WHAT THIS IS FOR, AND IT IS NOT A REDUNDANT `tn_isfinite-gate`. That gate asks six
questions about the TOP node and nothing else -- `op`, `arg`, `nsrc`, reachability,
`src[1]` is CONST, `src[1]` is not self -- and `tn_graph_census` asks ONE question about
the whole graph, which `Rng.sig` spells `15 Ops.CMPNE/2 Ops.OR Ops.CONST`: a count, the
root's op, the root's src count, the root's DIRECT src ops. Every other node is one
undifferentiated unit of that `15`.

MEASURED, THE DEFECT BOTH OF THOSE READ AS AGREEMENT. `tn_isfinite.isinf_part` compared
the positive arm's bool MUL against `-inf`, so its `CMPNE` read the MUL where CPython
reads a CONST: **the same count, the wrong srcs, four levels down.** The commit that fixed
it was `.agents/slop/tnisf/dump2.bend`, a 49-line probe under a directory that is being
pruned, and it is the only instrument in the tree that ever saw the class. These 15 rows
are that probe, wired.

THE ROW FORM AND WHY IT IS NOT A SET, WHICH IS THE WHOLE POINT. Each row is

    n<k>=<op>/<nsrc> srcs=<toposort positions> arg=<const> dt=<dtype>

and `gatekit` diffs two ORDERED lists, so row k is compared with row k. There is no sort,
no dedup and no multiset step anywhere on this path. The `srcs=` field names each src by
its POSITION rather than by its op, which is what catches a swap: `ADD(mul_a, mul_b)`
spelled `ADD(mul_b, mul_a)` keeps the ops, the multiset and the count, and only moves two
numbers. `arg=` is here because `+inf` and `-inf` are the same op at the same positions
and only their VALUES differ, so a port that handed the positive arm the negative constant
would be invisible without it.

THE COMPARISON CANNOT REPRODUCE THE PIN THAT HID THE BUG. `gates/tn_isfinite.bend` records
that its own earlier pin blamed an extra CAST because three extra casts and one missing
const CANCELLED to +2 and hid each other. There is no total here for a defect to hide in:
a substitution moves the row it lands in, and a count is one field of one row rather than
the row.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. Fifteen because `tn_isfinite(CInt{4})` has fifteen nodes; the gate
# fails loudly on a sixteenth rather than diffing a longer lane against a shorter one,
# because `gatekit` asserts the row COUNT before it diffs anything.
ROWS = tuple(f"n{i}" for i in range(15))

GATE = Gate(
    "tn_nodes-gate",
    bend="tn_nodes.bend",
    oracle="tn_nodes-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_nodes-gate: 15 rows, 3 lanes -- every node of tn_isfinite "
                        "(op/nsrc/srcs-by-toposort-position/arg/dtype) agrees with CPython's "
                        "Tensor.isfinite, in order and with no declared divergence"))