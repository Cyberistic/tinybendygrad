#!/usr/bin/env python3
"""schedstore-gate.py -- THE GATE for `tinybendygrad/schedule/__init__.bend`'s deferred region.

    .venv/bin/python gates/schedstore-gate.py

FIFTY ROWS, TWO LANES -- CPython and the port -- over EIGHT of the TWELVE
rule bodies of the region the port's own header DEFERS:
`tinygrad/schedule/__init__.py:82-301`.

    def is_store_after(u:UOp) -> bool:
      return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
                                    or u.src[1].op is Ops.STORE)

    def collect_stores(ctx:CallifyCtx, u:UOp):
      if is_store_after(u): ctx.stores.append(u)

WHAT THIS GATE IS FOR. The port ALREADY HAS ALL EIGHT BODIES --
`tinybendygrad/schedule/__init__.bend` has `is_store_after` at :1231,
`collect_stores` at :1376, `canonicalize_alloc` at :1833,
`lower_sink_to_linear` at :1443, `copy_kernel_to_store` at :1549,
`simplify_copy_kernel.ok` at :1575, `assert_all_same_devices` at :1669 and
`apply_binds` at :1717 -- and NO ROW GATED THEM. MEASURED 2026-10-30 on the
port's own output: the port emits 111 rows and 0 of them are `isa_*` or `cs_*`.
A rule body that no row reads is a body that no gate can go red on, so this
gate is what makes the ported bodies TESTABLE AT ALL, and the rows are what
makes the DEFERRAL's claim ("the ctx DICT is the wall") FALSIFIABLE.

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

THE OTHER FIVE BODIES GOT ROWS ON 2026-10-31, AND THE GATE FOUND TWO MORE
REAL DEFECTS IN THEM -- BOTH IN BODIES THAT NO ROW READ:

  * `copy_kernel_to_store` REWROTE WITH THE WRONG POLARITY. `cks_fire` IS
    upstream's "return None" PREDICATE and it drove the rewrite, so a
    SAME-device copy was rewritten and a CROSS-device one was not. The `cks_*`
    rows see it: 6 of 50 rows move.
  * `assert_all_same_devices` DEDUPED THE NODES AND NOT THE DEVICES, so two
    PARAMS on ONE device counted as TWO and the `>= 2` threshold RAISED on a
    single-device kernel. The `ads_same_*` rows see it: 2 of 50 rows move.

THE PORT'S SIDE IS NOT UPSTREAM'S SIDE. Upstream's `graph_rewrite` is a
PATTERN-MATCHER REWRITER the port does not have, so NO ROW HERE IS "the port's
output == upstream's output". Every row asks a QUESTION BOTH LANES CAN ANSWER:

  lsl_*  DID THE GUARD HOLD? upstream's `lower_sink_to_linear` returns None
         EXACTLY when the guard fires, so the lane prints 1 for "it rewrote",
         and the port prints 1 for "the answer is not None". The wall --
         `function.key` and `schedule_cache` -- is BEYOND the guard, and the
         guard is the whole of the ported body.
  cks_*  DID `copy_kernel_to_store` REWRITE? upstream returns None for "no
         rewrite" and a CALL for "rewritten".
  sck_*  DID `simplify_copy_kernel` RETURN None? -- the SAME guard line, over
         the OTHER rule, and the row is 1 where upstream returned None.
  ads_*  THE DEVICE COUNT AND THE RAISE. Upstream's `dedup` is
         `list(dict.fromkeys(x))` over the DEVICE VALUES, so TWO PARAMS ON ONE
         DEVICE ARE ONE DEVICE.
  ab_*  WHICH ARM of `apply_binds`. Upstream's `apply_binds` is a CLOSURE
         inside `resolve_linear_call` and is NOT importable, so the lane
         calls `resolve_linear_call` and reads the arm off its OUTPUT: arm 1
         returns a LINEAR, arm 2 returns `si` ITSELF, and arm 3 returns a NEW
         node. Three outputs, three arms, and no restatement of upstream's
         condition.

THE GATE IS FALSIFIABLE, AND THAT IS MEASURED. Reverting the port's
`is_store_after` to read `src[0].op` instead of `src[0].unsharded_base.op`
moves `isa_SA_alloc_call` from 0 to 1 -- the port's ALLOC is its own
`unsharded_base`, so the two readings agree on every OTHER fixture and this
one fixture is what separates them. Reverting `collect_stores` to write
`ctx.replacements` moves `cs_reps` from 0 to 1 and `cs_stores` from 5 to 0.

AND THE OTHER FIVE ARE FALSIFIABLE TOO, EVERY ONE OF THEM, MEASURED
2026-10-31:

  break                                              rows moved
  ------------------------------------------------  -----------
  `copy_kernel_to_store`'s polarity                    6 of 50
  `assert_all_same_devices`'s device dedup             2 of 50
  `assert_all_same_devices`'s `>= 2` threshold          1 of 50
  `lower_sink_to_linear`'s `precompile` conjunct       1 of 50
  `lower_sink_to_linear`'s `KernelInfo` conjunct       1 of 50
  `lower_sink_to_linear`'s `body is SINK` conjunct      1 of 50
  `apply_binds`'s arm 1 / arm 2                        2 of 50
  `apply_binds`'s arm 3                                1 of 50
  `apply_binds.of`'s body-op read                      2 of 50
  `cks_dev.eq`'s `None == None`                        2 of 50
  the `disk` set's membership test                     2 of 50
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
  "lsl_sink",
  "lsl_pre",
  "lsl_ki",
  "lsl_body",
  "cks_same",
  "cks_diff",
  "cks_disk",
  "cks_diskdisk",
  "cks_none",
  "cks_nonecpu",
  "sck_same",
  "sck_diff",
  "sck_disk",
  "sck_diskdisk",
  "sck_none",
  "sck_nonecpu",
  "ads_same_n",
  "ads_same_raises",
  "ads_diff_n",
  "ads_diff_raises",
  "ads_none_n",
  "ads_none_raises",
  "ab_arm1",
  "ab_arm2",
  "ab_arm3",
)

GATE = Gate(
  "schedstore-gate",
  bend="gates/schedstore.bend",
  oracle="gates/schedstore-oracle.py",
  rows=len(ROWS),
  pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
  sys.exit(main(GATE, "schedstore-gate: 50 rows, 2 lanes -- `is_store_after`, "
                      "`collect_stores`, `canonicalize_alloc`, `lower_sink_to_linear`, "
                      "`copy_kernel_to_store`, `simplify_copy_kernel`, "
                      "`assert_all_same_devices` and `apply_binds` from "
                      "`tinygrad/schedule/__init__.py:107-237`, the region the port "
                      "DEFERS. The ctx DICT is NOT the wall: the port's `CallifyCtx` "
                      "is a four-list record and these rows say so"))
