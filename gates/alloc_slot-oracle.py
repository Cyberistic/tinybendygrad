#!/usr/bin/env python3
"""alloc_slot-oracle.py -- CPython's answers to `gates/alloc_slot.bend`'s rows.

    .venv/bin/python gates/alloc_slot-oracle.py

THE SUBJECT IS `ParamArg.slot`, THE ALLOCATION IDENTITY. Upstream mints it from
`next(UOp.unique_num)` -- `tinygrad/uop/ops.py:1191`:

    arg=ParamArg(next(UOp.unique_num) if slot is None else slot, strong_dtype(dtype), ...)

and `UOp.unique_num` is `itertools.count(0)` (ops.py:820), a MONOTONE counter of
ALLOCATIONS. It is spent at exactly three sites -- ops.py:839 (`UOp.new_buffer`),
:1191 (`UOp.alloc`) and :1199 (`UOp.placeholder`) -- and NOWHERE ELSE, so it counts
ALLOCATIONS and not NODES.

MEASURED, and the counter is PROCESS-GLOBAL: `Tensor.empty(4,3)` twice in one
process gives the two ALLOCs slots 0 and 1, and the port gave both slot 1.

THE ORACLE RESETS THE COUNTER BEFORE EACH SCENARIO, and that is what makes the two
lanes comparable. Upstream's counter is global and the port's is scoped to its arena,
so "the first allocation of a fresh scope" is the one thing both sides can be asked
about -- and the reset is what puts upstream's counter at 0 for that question. The
port's equivalent is a fresh `O.Arena.empty()`.

THE ROW IS THE SLOT'S VALUE. A row that printed the OP would read `ALLOC` on both
sides for the wrong slot and would not move, so it could not see this defect at all.

THE `two_scopes` ROW IS THE WALL, AND IT IS A ROW AND NOT A COMMENT. Two allocations
built in SEPARATE scopes are 0 and 1 upstream (the counter is global) and 0 and 0 in
the port (each arena counts its own), because the port has one arena per method and
upstream has one process-wide store. `gates/alloc_slot.bend` prints that row as
`port-only`: the port lane answers it and the ORACLE DOES NOT, because the oracle
cannot ask the port's question. `gates/alloc_slot-gate.py` declares it in
`port_only=`, so the row is EXCLUDED from the diff and the ABSENCE is the claim.

THE CONTROL IS `alloc_same_scope_two`: the two allocations in ONE scope must get
DIFFERENT slots, because a slot is a buffer identity and two allocations sharing one
would bind to the same buffer. `gates/alloc_slot-gate.py` asserts it.
"""

import itertools

from tinygrad.uop.ops import Ops, UOp

# `UOp.unique_num` is a CLASS ATTRIBUTE holding an `itertools.count`. Rebinding it is
# the only way to put upstream's counter at a known value, and it is what the port's
# fresh arena does for the port.
def reset():
  UOp.unique_num = itertools.count(0)


def slots(g):
  """THE SLOTS of the graph's allocations, in toposort order."""
  return [u.arg.slot for u in g.toposort() if u.op in (Ops.ALLOC, Ops.BUFFER)]


def text(xs):
  return ",".join(str(x) for x in xs) if xs else "none"


# --- the scenarios -------------------------------------------------------
# Each one RESETS the counter first, so each row is "the slots of these allocations,
# counted from zero".

def one_empty():
  from tinygrad import Tensor, dtypes
  reset()
  return slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)


def two_empty_same_scope():
  from tinygrad import Tensor, dtypes
  reset()
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  b = Tensor.empty(4, 3, dtype=dtypes.float)
  return slots(a.uop) + slots(b.uop)


def three_empty_same_scope():
  from tinygrad import Tensor, dtypes
  reset()
  out = []
  for _ in range(3):
    out += slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)
  return out


def full_then_empty():
  from tinygrad import Tensor, dtypes
  reset()
  out = slots(Tensor.full((2, 3), 42.0).uop)
  out += slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)
  return out


def empty_then_full():
  from tinygrad import Tensor, dtypes
  reset()
  out = slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)
  out += slots(Tensor.full((2, 3), 42.0).uop)
  return out


def two_empty_two_scopes():
  """THE WALL, MEASURED AND NOT A GATE ROW. Upstream's counter is process-global, so two
  allocations in two scopes are 0 and 1; the port's is arena-scoped, so they are 0 and 0.

  This is NOT printed: the port lane cannot be asked upstream's question, and a row both
  sides print with different answers would be RED BY CONSTRUCTION. The port answers the
  question it CAN be asked -- `alloc_two_scopes` -- and the gate declares that row
  PORT-ONLY, so the ABSENCE of the upstream answer is the claim.
  """
  from tinygrad import Tensor, dtypes
  reset()
  a = slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)
  b = slots(Tensor.empty(4, 3, dtype=dtypes.float).uop)
  return a + b


ROWS = (
  ("alloc_one_empty", one_empty),
  ("alloc_two_same_scope", two_empty_same_scope),
  ("alloc_three_same_scope", three_empty_same_scope),
  ("alloc_full_then_empty", full_then_empty),
  ("alloc_empty_then_full", empty_then_full),
)

if __name__ == "__main__":
  for name, fn in ROWS:
    print(f"{name}={text(fn())}")
