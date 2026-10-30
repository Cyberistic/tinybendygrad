#!/usr/bin/env python3
"""alloc_slot-gate.py -- THE GATE for `ParamArg.slot`, the ALLOCATION IDENTITY.

    .venv/bin/python gates/alloc_slot-gate.py

SIX ROWS, TWO LANES -- CPython and the port -- over ONE property: the slot an
allocation is given.

THE DEFECT THIS GATE EXISTS FOR. `tinygrad/uop/ops.py:1191` mints an ALLOC's slot from
`next(UOp.unique_num)`, and `UOp.unique_num` is `itertools.count(0)` (ops.py:820) -- a
MONOTONE counter of ALLOCATIONS, spent at exactly three sites (ops.py:839
`UOp.new_buffer`, :1191 `UOp.alloc`, :1199 `UOp.placeholder`).

The port minted it from `O.Arena.next(ar)` -- the arena's LENGTH -- on the argument that
`tinybendygrad/uop/ops.bend:1359` says "the arena's length IS that counter". THE
ARGUMENT IS FALSE. An arena's length counts EVERY node; upstream's counter counts
ALLOCATIONS. MEASURED, `Tensor.empty(4,3)`:

    CPython   ALLOC slot 0
    the port  ALLOC slot 1

and the port gave a SECOND `empty` slot 1 as well, because `Arena.next` counted the
arena's BOTTOM rather than an allocation.

THE ROW IS THE SLOT'S VALUE, not the OP. An OP row reads `ALLOC` on both sides for the
WRONG slot and does not move, so it could not see this defect at all.

THE ORACLE RESETS UPSTREAM'S COUNTER BEFORE EACH SCENARIO, and that is what makes the
two lanes comparable at all. Upstream's counter is process-global and the port's is
scoped to its arena, so the comparable question is "the slots of these allocations,
counted from zero in one scope" -- and the oracle's reset and the port's fresh
`O.Arena.empty()` are the same answer to that question.

`alloc_two_scopes` IS THE WALL AND IT IS PORT-ONLY. Two allocations built in SEPARATE
scopes are slots 0 and 1 upstream (the counter is global) and 0 and 0 in the port (each
arena counts its own), because the port has one arena per method and upstream has one
process-wide store. The port lane prints the row and the oracle does not, so it is
excluded from the diff and the ABSENCE is the claim -- `gatekit`'s `port_only` shape,
which asserts the absence on the oracle side by the DERIVED row count.

THE CONTROL IS `alloc_two_same_scope`: the two allocations in ONE scope must get
DIFFERENT slots, because a slot is a buffer identity and two allocations sharing one
would bind to the same buffer. A port that minted a constant would satisfy every diff
and fail this, so the control is what makes the diff mean something.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

# THE FIVE SHARED ROWS. `alloc_two_scopes` is PORT-ONLY and is named in `port_only`.
SHARED = (
  "alloc_one_empty",
  "alloc_two_same_scope",
  "alloc_three_same_scope",
  "alloc_full_then_empty",
  "alloc_empty_then_full",
)
PORT_ONLY = ("alloc_two_scopes",)

GATE = Gate(
  "alloc_slot-gate",
  bend="gates/alloc_slot.bend",
  oracle="gates/alloc_slot-oracle.py",
  rows=len(SHARED) + len(PORT_ONLY),
  compared=len(SHARED),
  port_only=PORT_ONLY,
  pins=[(lane, row) for lane in ("py", "bd", "bn") for row in SHARED]
       + [(lane, row) for lane in ("bd", "bn") for row in PORT_ONLY],
)


def control_ok() -> bool:
  """THE POSITIVE CONTROL, and it reads the LANE the run produced.

  `alloc_two_same_scope` must be `0,1` and not `0,0`: two allocations in one scope need
  two DIFFERENT slots, because a slot is a buffer identity. An instrument that cannot
  tell a constant from a counter cannot tell the tree apart either, and this row is
  the one the diff would let through.
  """
  path = GATE.dir / "bd.out"
  if not path.is_file():
    return False
  for line in path.read_text().splitlines():
    if line.startswith("alloc_two_same_scope="):
      return line.split("=", 1)[1].strip() == "0,1"
  return False


if __name__ == "__main__":
  sys.exit(gate(GATE, "alloc_slot-gate: 6 rows, 2 lanes -- the ALLOCATION IDENTITY "
                      "(`ParamArg.slot`), which upstream mints from a monotone counter of "
                      "ALLOCATIONS and the port minted from the arena's LENGTH",
               checks=control_ok))
