#!/usr/bin/env python3
"""rd_graph_census-oracle.py -- CPython's OP SEQUENCE for the `_threefry_random_bits` path.

    .venv/bin/python gates/rd_graph_census-oracle.py

THE SAME ROWS `gates/rd_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort op sequence; this lane prints CPython's for the SAME graph, so a divergence is
a SHAPE divergence and not a prose claim.

THE ROWS ARE `tinygrad/mixin/rand.py`'s OWN TWO LINES, ONE ROW EACH, PLUS THE REAL METHOD:

    p64    rand.py:13  `(counts1.cast(uint64) << 32) | counts0.cast(uint64)`   = `rd_p64`
    x      rand.py:13  the same expression with the call's `(counts0, counts1)` order = `rd_tfb.x`
    three  rand.py:14  `x.threefry((key[1].cast(uint64) << 32) | key[0].cast(uint64))` = `rd_tfb.three`
    tfb    rand.py:12  `_threefry_random_bits(key, counts0, counts1)` -- THE REAL METHOD, called
                       so the three transcribed rows above are anchored to it.

THE ORACLE CALLS THE HIGH-LEVEL PATH AND NEVER A LOWER-LEVEL HELPER. `p64`/`three` are spelled
with the Tensor operators `_threefry_random_bits` itself uses (`<<`, `|`, `.cast`, `.threefry`),
NOT with `alu(Ops.OR)`/`alu(Ops.SHIFT)` -- the trap is a port and an oracle that BOTH call the
low-level node builder and agree while both are wrong (a unit was burned by an oracle calling
`alu(Ops.SUB)` where CPython's `sub` builds `ADD(a, MUL(b,-1))`). `tfb` calls the method
`tinygrad/mixin/rand.py:12` itself, so the transcription cannot drift unnoticed.

THE FIXTURES ARE `empty`, MATCHING THE PORT'S DRIVER AND NOT `arange`. `random_bits` builds the
counts from `arange` (rand.py:26), but the port's `arange` has its own known divergence, so a
gate over the OR ARENA RULE uses `empty` (ONE `ALLOC` in both lanes) and leaves `arange` to its
own gate. `counts1 = counts0 + 1` and `key = empty(2, uint32)` are the same node shapes the
port's `rd_c1`/`rd_key` build.

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph -- a `toposort()` with each
node's op and src COUNT -- so no device is needed and the oracle is pure Python.
"""

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.mixin.rand import RandMixin


def sig(t) -> str:
    us = t.uop.toposort()
    return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def fixtures():
    """The two `random_bits` counters and the key, as the port's rows build them."""
    key = Tensor.empty(2, dtype=dtypes.uint32, device='PYTHON')
    counts0 = Tensor.empty(3, dtype=dtypes.uint32, device='PYTHON')
    counts1 = counts0 + 1
    return key, counts0, counts1


def p64(hi, lo):
    """rand.py:13 -- the first line of `_threefry_random_bits`, in Tensor operators."""
    return (hi.cast(dtypes.uint64) << 32) | lo.cast(dtypes.uint64)


def three(x, key):
    """rand.py:14 -- the second line of `_threefry_random_bits`, in Tensor operators."""
    return x.threefry((key[1].cast(dtypes.uint64) << 32) | key[0].cast(dtypes.uint64))


def row(name, t):
    print(f"{name}={sig(t)}")


key, counts0, counts1 = fixtures()
row("p64", p64(counts1, counts0))

key, counts0, counts1 = fixtures()
row("x", p64(counts1, counts0))

key, counts0, counts1 = fixtures()
row("three", three(p64(counts1, counts0), key))

key, counts0, counts1 = fixtures()
row("tfb", RandMixin._threefry_random_bits(key, counts0, counts1))
