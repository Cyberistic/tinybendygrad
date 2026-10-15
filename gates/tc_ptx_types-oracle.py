#!/usr/bin/env python3
"""tc_ptx_types-oracle.py -- CPython's answers to `gates/tc_ptx_types.bend`'s sixty rows.

    .venv/bin/python gates/tc_ptx_types-oracle.py

Run with the repo's venv so the import is the working tree's tinygrad.

SIXTY ROWS, THREE TABLES, TWENTY DTYPES, AND THE POPULATION IS DISCOVERED -- NOT WRITTEN
DOWN. It is `sorted(dtypes.all)` plus `DType.weaks` plus `dtypes.void`, which is twenty
entries; the driver `gates/tc_ptx_types.bend` names the same twenty and the gate's DERIVED
row count is what holds the two in register, so a dtype this file gains and the driver does
not is one row too many and fails. That is the whole point of not writing the list twice.

THE EIGHT MISSES ARE FOUND, NOT NAMED: `d not in PTXRenderer.types` is the question, and it
is `PTXRenderer`'s own dict that answers it, so this lane cannot agree with the port about
which dtypes are misses -- it asks.

A `KeyError` is CAUGHT and printed, because a refusal is an answer and the whole gate turns
on being able to see one. Letting it propagate would make a lane that emitted 42 of 60 rows
look like a lane that crashed.
"""

from tinygrad.dtype import dtypes
from tinygrad.renderer.ptx import PTXRenderer

# THE POPULATION IS DISCOVERED, NOT WRITTEN DOWN: it is `dtypes.all` (17) plus
# `dtypes.weaks` (2) plus `dtypes.void` (1), which is twenty entries. The driver
# `gates/tc_ptx_types.bend` names the same twenty out of `LAWS/spec.bend`, and the gate's
# DERIVED row count is what holds the two in register: a dtype this file gains and the
# driver does not is one row too many and fails the gate. That is why the list is not
# written down twice.
#
# NAME ORDER, because `gatekit` compares two ORDERED lists and neither lane may be told the
# order: each sorts by the dtype's own name (`DType.name` here, `T.dt_name` there), which
# is the one order neither side can get wrong. MEASURED equal on all twenty.
POP = sorted([dtypes.void, *dtypes.all, *dtypes.weaks], key=lambda d: d.name)

TABLES = (("types", PTXRenderer.types), ("mem_types", PTXRenderer.mem_types), ("cast_types", PTXRenderer.cast_types))


def ask(table, dtype):
    """CPython's answer, or the refusal it raises. `KeyError` IS the answer for eight of
    the twenty, so catching it is not error handling -- it is the measurement."""
    try:
        return table[dtype]
    except KeyError:
        return "KeyError"


for name, table in TABLES:
    for d in POP:
        print(f"{name}_{d.name}={ask(table, d)}")