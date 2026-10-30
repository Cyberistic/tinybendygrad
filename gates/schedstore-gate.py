#!/usr/bin/env python3
"""schedstore-gate.py -- THE GATE for `tinybendygrad/schedule/__init__.bend`'s deferred region.

    .venv/bin/python gates/schedstore-gate.py

TWELVE ROWS, TWO LANES -- CPython and the port -- over ONE rule of the region
the port's own header DEFERS: `tinygrad/schedule/__init__.py:213-217`.

    def is_store_after(u:UOp) -> bool:
      return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
                                    or u.src[1].op is Ops.STORE)

    def collect_stores(ctx:CallifyCtx, u:UOp):
      if is_store_after(u): ctx.stores.append(u)

WHAT THIS GATE IS FOR. The port ALREADY HAS BOTH BODIES --
`tinybendygrad/schedule/__init__.bend` has `is_store_after` at :1206 and
`collect_stores` at :1351, and `CallifyCtx` at :1239 -- and NO ROW GATED
THEM. MEASURED 2026-10-30 on the port's own output: the port emits 111 rows
and 0 of them are `isa_*` or `cs_*`. A rule body that no row reads is a body
that no gate can go red on, so this gate is what makes the ported bodies
TESTABLE AT ALL, and the twelve rows are what makes the DEFERRAL's claim
("the ctx DICT is the wall") FALSIFIABLE.

THE CTX DICT IS NOT THE WALL, AND THESE ROWS ARE THE MEASUREMENT. The port's
`CallifyCtx` is a `Data` record of FOUR append-only lists, and `collect_stores`
returns the ctx and the answer TOGETHER (`Cw`) because Python's
one-call-one-side-effect signature cannot be spelled in Bend. `cs_reps`,
`cs_allocs` and `cs_views` are the IDENTITY rows: CPython's `CallifyCtx` has
four fields and `collect_stores` writes ONE of them, so the other three are
empty, and a port that modelled the ctx as one list, or that wrote the wrong
field, answers 1 where CPython answers 0.

THE `isa_*` ROWS ARE FOUR ARMS OF ONE `or`. `AFTER(ALLOC, CALL)` is the ONE
AFTER upstream rejects, and it is rejected by the FIRST conjunct alone --
`unsharded_base(ALLOC)` is the ALLOC itself, because an ALLOC is not in
`GroupOp.Movement`. `isa_SA_alloc_call` is therefore the row that pins the
walk's STOP SET, and `isa_SA_alloc_store` is its neighbour: the same ALLOC,
but with a STORE in `src[1]`, so the SECOND conjunct carries it.

THE GATE IS FALSIFIABLE, AND THAT IS MEASURED. Reverting the port's
`is_store_after` to read `src[0].op` instead of `src[0].unsharded_base.op`
moves `isa_SA_alloc_call` from 0 to 1 -- the port's ALLOC is its own
`unsharded_base`, so the two readings agree on every OTHER fixture and this
one fixture is what separates them. Reverting `collect_stores` to write
`ctx.replacements` moves `cs_reps` from 0 to 1 and `cs_stores` from 5 to 0.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
  "isa_SA_buffer_call",
  "isa_SA_buffer_store",
  "isa_SA_alloc_call",
  "isa_SA_alloc_store",
  "isa_SA_buffer_end",
  "isa_SA_sink_call",
  "isa_K",
  "isa_SA_reshape_alloc",
  "isa_SA_reshape_buffer",
  "isa_SA_reshape_alloc_store",
  "cs_reps",
  "cs_allocs",
  "cs_views",
  "cs_stores",
  "cs_ord",
  "ca_slot1",
  "ca_slot2",
  "ca_slot3",
  "ca_neg_none",
  "ca_n1",
  "ca_n2",
  "ca_n3",
  "ca_n4",
  "ca_reps",
  "ca_views",
)

GATE = Gate(
  "schedstore-gate",
  bend="gates/schedstore.bend",
  oracle="gates/schedstore-oracle.py",
  rows=len(ROWS),
  pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
  sys.exit(main(GATE, "schedstore-gate: 25 rows, 2 lanes -- `is_store_after`, "
                      "`collect_stores` and `canonicalize_alloc` from "
                      "`tinygrad/schedule/__init__.py:213-237`, the region the port "
                      "DEFERS. The ctx DICT is NOT the wall: the port's `CallifyCtx` "
                      "is a four-list record and these rows say so"))
