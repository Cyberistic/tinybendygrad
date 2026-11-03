#!/usr/bin/env python3
"""schedsched-gate.py -- THE GATE for `create_schedule`, the scheduler engine itself.

    .venv/bin/python gates/schedsched-gate.py

111 ROWS IN THE PORT, 84 OF THEM COMPARED AGAINST CPYTHON, over
`tinygrad/schedule/__init__.py:32-80` -- the function `lower_sink_to_linear` calls and the one
`create_linear_with_vars` reaches through it.

WHAT WAS WRONG, AND IT IS THE REASON THIS FILE EXISTS. `tinybendygrad/schedule/__init__.bend`
emits 111 rows from its own `main()`: the fixtures `fx0`..`fx8`, the four dicts' sizes, the
gated toposort, and the LINEAR that `create_schedule` returns. NOT ONE OF THEM WAS COMPARED
AGAINST CPYTHON -- `gates/schedstore-oracle.py` covers the twelve rule bodies and never calls
`create_schedule`. Worse, the expectations in the port's comments were a reading of
`.agents/slop/notes/sched-truth.py`, and that script is GONE: `find .agents -name 'sched-truth*'`
answers nothing. So 111 rows were a memory of a deleted script, which is the same shape as
`rebase-gate-selftest.py`'s "0 disagreements over 0 comparisons". MEASURED BEFORE THIS GATE:
83 of the 84 comparable rows happened to be right, so the rows were not free -- they were
UNFALSIFIABLE, which is the worse defect.

THE 27 PORT-ONLY ROWS ARE NAMED, NOT DROPPED. Three kinds, and each kind is a reason:

  fx1_nodes/fx2_nodes/fx5_nodes  an ARENA SLOT COUNT. CPython has no arena, so there is no
                                 number to agree with; the port's own header already says these
                                 are "port-only bookkeeping".
  COUNT_*  (24 rows)             the sizes of `children`, `in_degree`, `writes` and `reads`.
                                 Those four are LOCALS inside `create_schedule`, so computing
                                 their sizes here would be RE-IMPLEMENTING the algorithm
                                 instead of asking it -- an oracle that copies the code it
                                 checks. The rows stay because a port-side rebuild bug shows
                                 up there first (two did: the `[new] ++ r` order and the
                                 `Nil{}` re-insert), they are just not evidence about CPython.
  split_bad_ks                   CPython RAISES on that fixture (`AFTER source should be
                                 CALL, END, STORE, or AFTER`) and the port deliberately DROPS
                                 the SINK. Two lanes answering different questions cannot
                                 agree, so this row pins the port's documented choice.

AND THE ORACLE FOUND A DEFECT IN ITSELF FIRST, WHICH IS WHY IT IS TRUSTWORTHY. Its first
revision built a BUFFER as `UOp(Ops.BUFFER, src=(UOp(Ops.SPECIAL, ...),))` -- the form the
comment above the port's `g_buf` describes -- and every `fx*_topo` row moved by one. `UOp._buffer`
(ops.py:831) is `src=(shape_to_shape_arg((size,)),)+device_range_src(device)`, and
`device_range_src` is `()` for a single STRING device (:829), so a BUFFER's src is ONE CONST and
there is NO SPECIAL. **The port was right and the oracle was not**, and the mismatch was caught
by a row (`fx*_topo`) that counts nodes rather than asserting an idea.

THE ONE ROW THAT WOULD HAVE SLIPPED THROUGH WITHOUT THIS GATE. `fx8_lin_n=0` is the
`gate_kernel_sink` witness: a SINK whose arg is a KernelInfo is REJECTED, so its subtree is
never visited and its kernel is never scheduled. A port whose gate answers True for every SINK
schedules one. Before this gate the only evidence for that was the port comparing itself to
itself.

FIVE PLANTS, THREE RED, AND THE TWO THAT ARE NOT ARE NAMED. MEASURED, each a TEXT edit to
`tinybendygrad/schedule/__init__.bend` and the rows it moves:

  `sc_gate.of`'s SINK arm -> `True{}`          7 rows: gate_ki and all six fx8_*
  `wt_keep`'s slice suppression dropped        8 rows: fx5_lin_n/marks/nsrcs/ops + 4 COUNT_fx5
  `ww.of`'s WAR arm -> `c`                     5 rows: fx2_marks + 4 COUNT_fx2
  `sc_kdeps.of`'s END arm reads the END        0 rows  <- NO FIXTURE SEES IT
  `sc_gate.of`'s LINEAR arm -> `True{}`        0 rows  <- NO FIXTURE HAS A LINEAR IN THE WALK

So the END arm and the LINEAR arm are ported CODE WITH NO ROW, and this file says so rather
than implying otherwise. The END arm is unreachable in the compared set because `e2`'s read
states feed only the WAR pass and fx1 has no competing write on those states; a sixth fixture
with an `END` whose kernel READS a state that is later superseded is what would see it. The
LINEAR arm needs a graph that has already been linearized -- a `create_schedule` of a
`create_schedule` output.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

PORT_ONLY = (
    "fx1_nodes", "fx2_nodes", "fx5_nodes", "split_bad_ks",
    "COUNT_fx1_kids", "COUNT_fx1_degs", "COUNT_fx1_wrns", "COUNT_fx1_rds",
    "COUNT_fx1_zero", "COUNT_fx1_cyc", "COUNT_fx1_kidn",
    "COUNT_fx2_kids", "COUNT_fx2_degs", "COUNT_fx2_wrns", "COUNT_fx2_rds",
    "COUNT_fx2_zero", "COUNT_fx2_cyc", "COUNT_fx2_kidn",
    "COUNT_fx3_wrns", "COUNT_fx3_wrks",
    "COUNT_fx5_kids", "COUNT_fx5_degs", "COUNT_fx5_wrns", "COUNT_fx5_rds",
    "COUNT_fx5_zero", "COUNT_fx5_cyc", "COUNT_fx5_kidn",
)

# Every row the port emits. Kept as the DECLARATION so a row that disappears is a red gate,
# not a smaller denominator -- `rows=111` is what makes a deleted row visible.
ROWS = 111

# The rows a diff cannot vouch for on its own: if BOTH lanes stopped emitting one of these, the
# diff would still be green and the claim would be gone. `fx8_lin_n` is the `gate_kernel_sink`
# witness (zero kernels), `fx2_kidn`-adjacent `fx2_ops` is the WAR edge showing up in the LINEAR,
# and `fx0_lin_n` is the empty schedule.
PINS = tuple((lane, row) for lane in ("py", "bd")
             for row in ("fx0_lin_n", "fx1_ops", "fx2_ops", "fx5_ops", "fx8_lin_n"))

GATE = Gate(
    "schedsched-gate",
    bend="tinybendygrad/schedule/__init__.bend",
    oracle="gates/schedsched-oracle.py",
    rows=ROWS,
    compared=ROWS - len(PORT_ONLY),
    port_only=PORT_ONLY,
    pins=PINS,
)

if __name__ == "__main__":
    sys.exit(main(GATE, "schedsched-gate: 111 rows, 84 compared -- `create_schedule` "
                        "(`tinygrad/schedule/__init__.py:32-80`) over the fixtures fx0..fx8: "
                        "the gated toposort, the RAW and WAR passes, and the LINEAR it "
                        "returns. 27 rows are port-only and NAMED: arena slot counts, the "
                        "four dicts' sizes (locals, not observable), and the fixture CPython "
                        "raises on"))
