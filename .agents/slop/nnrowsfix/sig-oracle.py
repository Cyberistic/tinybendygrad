#!/usr/bin/env python3
"""sig-oracle.py -- CPython's OWN graph for the five `nn/layers.bend` `_sig` rows.

The port's rows print `mxw_sig`'s spelling:

    n=<count> op=Ops.<root> nsrc=<n> srcops=Ops.<a>|Ops.<b>

and this script prints CPython's graph in THE SAME SPELLING, so the two sides are
comparable as strings and not merely as "both are graphs":

    n      = len(t.uop.toposort())
    op     = t.uop.op.name
    nsrc   = len(t.uop.src)
    srcops = "|".join("Ops." + s.op.name for s in t.uop.src)

It also prints CPython's own oracle-format signature (`n OP/nsrc OP/nsrc ...`, the
shape `gates/mixin-op-oracle.py` prints) so the two formats can be compared side by
side and so that a reader can see the node LISTS, not only the counts.

THE FIXTURES ARE THE PORT'S FIXTURES, restated in CPython's constructors.
`nn_row.t(ns, slot, size)` is the port's `mxw_reshape(mxw_buf(ar, slot, size), ns)`:
a BUFFER of `size` elements RESHAPED to `ns`. CPython's `Tensor(np.zeros(size))`
is `UOp.new_buffer("NPY", size, dtype).reshape(shape)` (tinygrad/tensor.py:37-40),
which is the same node -- upstream's `Ops.BUFFER`, whose size is a CONST SRC
(tinygrad/uop/ops.py:830-832). So the leaf op NAME agrees on both sides and no name
has to be substituted.

Run:  .venv/bin/python .agents/slop/nnrowsfix/sig-oracle.py
"""
import sys

import numpy as np

sys.path.insert(0, '.')
from tinygrad import Tensor  # noqa: E402


def port_sig(t):
    """CPython's graph in the PORT's signature spelling (`mxw_sig`'s)."""
    us = t.uop.toposort()
    root = t.uop
    srcops = "|".join("Ops." + s.op.name for s in root.src)
    return f"n={len(us)} op=Ops.{root.op.name} nsrc={len(root.src)} srcops={srcops}"


def oracle_sig(t):
    """CPython's graph in the ORACLE's spelling (`gates/mixin-op-oracle.py`)."""
    us = t.uop.toposort()
    return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def show(name, t):
    print(f"{name}_portspell={port_sig(t)}")
    print(f"{name}_oracle={oracle_sig(t)}")


def buf(size, shape):
    """THE PORT'S `nn_row.t(shape, slot, size)`: a BUFFER of `size` RESHAPED to `shape`."""
    return Tensor(np.zeros(size, dtype=np.float32)).reshape(shape)


def main():
    x = buf(6, (2, 3))
    w = buf(12, (3, 4))
    show('x', x)
    show('dot', x.dot(w))
    xr = x.reshape(2, 1, 3)
    wr = w.reshape(1, 3, 4).permute(0, 2, 1)
    xw = xr * wr
    show('xw', xw)
    show('sm', xw.sum(axis=2))
    show('cc', xw.sum(axis=2).cast('float32'))
    xc = buf(3072, (1, 3, 32, 32))
    wc = buf(216, (8, 3, 3, 3))
    show('conv', xc.conv2d(wc, padding=1))


if __name__ == '__main__':
    main()
