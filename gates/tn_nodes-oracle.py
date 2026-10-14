#!/usr/bin/env python3
"""tn_nodes-oracle.py -- CPython's per-NODE rows for `Tensor.isfinite`, one per node.

    .venv/bin/python gates/tn_nodes-oracle.py

THE SAME 15 ROWS `gates/tn_nodes.bend` PRINTS, FROM CPYTHON. The bend lane walks the
port's `tn_isfinite` graph; this lane walks the graph tinygrad's `Tensor.isfinite`
builds (`(self.isinf() | self.isnan()).logical_not()`, elementwise.py:623) and asks the
same four questions of every node.

    n<k>=<op>/<nsrc> srcs=<positions> arg=<const> dt=<dtype>

`k` IS THE TOPOSORT POSITION. Both sides run the same DFS postorder -- MEASURED, the port's
`Arena` indices come out `2 3 4 5 6 7 8 9 10 11 12 1 13 14 15` and this file's positions
`0..14`, because the port allocates the input CONST first and both VISIT it eleventh -- so
`k` is the one name the two graphs provably share and `srcs=` is that name applied to
each edge. A node that keeps its op and its src COUNT while reading the WRONG src moves a
number in `srcs=`, which is the defect the whole file exists for: MEASURED, `isinf_part`
once spelled `CMPNE(MUL, CONST)` where CPython has `CMPNE(CONST, CONST)` -- the same count,
the wrong srcs, four levels down, and invisible to `gates/tn_isfinite.bend`'s six rows AND
to `gates/tn_graph_census.bend`'s one.

`argstr` IS A GLYPH TRANSLATION AND NOT A SECOND GRAPH DERIVATION. The structure of every
row -- which node, which op, which src, which dtype -- is CPython's own; what this file
adds is the spelling of an `Arg`, because the port's arena holds `CFloat`/`CInt`/`CBool`
and Python holds `float`/`int`/`bool`. Four shapes are translated and nothing else:
`None -> -`, `bool -> b0|b1`, `int -> i<hi>:<lo>` (the port's `H.i64_text`), and
`float -> f<repr with a trailing .0 dropped>` (the port's `F32.show`; MEASURED, `4.0`
prints `f4` and `inf` prints `finf`). Anything else returns `?<repr>`, which cannot match
the port, so a const shape this file does not know about is a DISAGREEMENT rather than a
silent agreement. A TRANSLATION is safe here in a way a translation of the graph would not
be: it can only make the two lanes differ, never make them agree for the wrong reason.

THE INPUT IS `CONST{4}`, and so is the driver's (`tn_graph_census`'s `t4`), so both lanes
build the same graph. `dstype` is `dtypes.float` via `_broadcasted`'s promote half, so the
graph holds a `weakfloat` leaf and an `weakint` leaf two hash-cons apart -- a shape a
count-only census cannot distinguish from a graph that is one node short.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def argstr(a) -> str:
    """The PORT's `Arg` spelling of CPython's `arg`. See the header; four shapes only."""
    if a is None:
        return "-"
    if isinstance(a, bool):
        return f"b{int(a)}"
    if isinstance(a, int):
        return f"i{a >> 32}:{a & 0xFFFFFFFF}"
    if isinstance(a, float):  # ConstFloat is a float subclass and overrides __repr__
        return "f" + repr(float(a)).removesuffix(".0")
    return f"?{a!r}"


def toposort(u, seen, out):
    """DFS postorder, exactly `UOp.toposort` and exactly the port's `UOp.toposort`.

    The id-set is the hash-cons: `self.eq(+inf)` and `self.eq(-inf)` share ONE
    `weakfloat 4.0` leaf, and `self != self` compares the `weakint 4` against ITSELF
    (`n12`'s `srcs=11|11`), which is why this is a set and not a count.
    """
    if id(u) in seen:
        return
    seen.add(id(u))
    for s in u.src:
        toposort(s, seen, out)
    out.append(u)


t4 = Tensor(UOp(Ops.CONST, src=(), arg=4), device="PYTHON")
nodes, seen = [], set()
toposort(t4.isfinite().uop, seen, nodes)
pos = {id(u): k for k, u in enumerate(nodes)}

for k, u in enumerate(nodes):
    srcs = "|".join(str(pos[id(s)]) for s in u.src) or "-"
    print(f"n{k}=Ops.{u.op.name}/{len(u.src)} srcs={srcs} arg={argstr(u.arg)} dt={u.dtype.name}")