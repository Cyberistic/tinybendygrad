#!/usr/bin/env python3
"""gkg-gate.py -- THE GATE for `get_kernel_graph`'s ENGINE, which is the seven stages
`tinybendygrad/schedule/rangeify.bend` drives (`eng_stages`, `eng_run`, `eng_fix`).

    .venv/bin/python gates/gkg-gate.py

WHAT WAS WRONG, AND IT IS THE REASON THIS FILE EXISTS. `rangeify.bend` printed 159 rows and
NO GATE DIFFED ANY OF THEM against CPython -- `gates/rng_graph_census-gate.py` and its
neighbours compare CENSUSES (how many copies of a rule exist), not answers. The `eng_*` rows
are `get_kernel_graph` driving two fixtures through all seven stages, i.e. the pipeline
itself, and they were a reading of the port's own behaviour. MEASURED, this lane found TWO
REAL DEFECTS in one run, and both were invisible to every row already in the file:

  1. `eng_run` SWEPT THE WHOLE ARENA, so it rewrote a CALL's `src[0]` -- the kernel BODY.
     CPython does not enter a call body unless `enter_calls` (`ops.py:298`,
     `node.src_without_body`), so a body-only node is NEVER rewritten. On fx_a the sweep
     turned `CALL(INDEX(CONST), RESHAPE)` into `CALL(CONST, RESHAPE)`; 6 of 16 rows
     disagreed. FIXED: the sweep is `O.UOp.toposort_nocalls`, the same walk the rest of the
     port uses, which is also the ONLY order in which every node's children are final.

  2. `remove_noop_afters` ASKED `one` BEFORE `shrank`. Upstream is
     `if len(src) != len(x.src): return src[0] if len(src) == 1 else x.replace(src=src)`, so
     `return None` is the ELSE -- a ONE-SRC AFTER that LOST NOTHING is not rewritten. Asking
     `one` first collapses every untouched one-src AFTER into its `src[0]`. That was the other
     8 rows, and `gates/gkg-oracle.py`'s stage 3 is what said so.

WHY THE EXISTING ROWS COULD NOT SEE EITHER. MEASURED: after both fixes, 14 rows moved and
every one of them is an `eng_*` stage row -- NOT ONE `raf_*` or `ab9_*` row moved. The
`remove_noop_afters` rows all reach `one` through a fixture that ALSO SHRANK, so `one` and
`one AND shrank` answer the same on all of them. A ROW SET CAN BE COMPLETE ABOUT THE ANSWERS
A RULE GIVES AND BLIND TO THE ONE INPUT IT NEVER BUILDS.

WHAT IS COMPARED: 16 ROWS. `eng_<a|b>_in` (the fixture as built) and `eng_<a|b>_s0..s6` (one
per stage). Both lanes build the same two graphs from the same source arguments and dump them
as `op:argkey:srcops`, BFS from the root, each node once -- the port's own `eng_dump` and this
oracle's `dump`.

WHAT IS NOT, AND THE LIST IS THE DENOMINATOR. 143 rows are PORT-ONLY, in three kinds:

  eng_<a|b>_r0..r6 (14)   `<moved>;<kept>` about THIS engine's memoisation map. CPython has no
                          map to count. The rows stay because they are the number that moves
                          FIRST when the memoisation is wrong -- they are what a future
                          regression on either fix above would show.
  eng_stages / eng_tables / eng_order (3)   how many stages and tables the PORT declares. Not
                          a CPython number.
  the per-rule rows (126) `ct_*`, `rb_*`, `lb_*`, `ab*_*`, `aprt_*`, `nic_*`, `sk_*`,
                          `nv_*`, `raf_*`, `szs_*`, `ren_*`, `dg*_*`, `fb_*`, `mops_*`,
                          `noopf*`, `rej_*`, `claim_*`, `can_*`, `stages`, `gs_len`.
                          EACH IS A FIXTURE FOR ONE RULE and NONE has a CPython lane. They
                          are a NAMED BACKLOG and not a claim of this gate; count them here
                          or the 16 reads as the population.

AND THE TWO MATCHERS `get_kernel_graph` RUNS FIRST ARE STILL ABSENT: `symbolic` and
`pm_reduce_simplify` have no port (`rg 'def symbolic\\b' tinybendygrad/` answers nothing), so
the port's stage 2 lists `[0, 1]` and not the four upstream names. THIS GATE COMPARES THE
SUBSET THE PORT DECLARES, which is the only thing it can compare, and the rows therefore say
nothing about the two absent tables.

`bottom_up` IS MEASURED NOT TO MATTER HERE, ON BOTH SIDES. The port drives every stage as a
pre-order fixed point; CPython's `bottom_up=True` is that same thing. MEASURED with
`gates/gkg-oracle.py --both`: 0 of 16 rows differ between CPython's `bottom_up=True` and
`bottom_up=False` on these two fixtures. So `Stg.mode` -- declared at :2791 and read by
NOTHING -- is an unobservable field ON THIS FIXTURE SET, and that is now a measurement rather
than the note at :2743 it used to be.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = 159
COMPARED = 16

PORT_ONLY = (
    "lay",
    "ct_len",
    "rb_len",
    "nic_len",
    "nv_len",
    "lb_len",
    "fb_len",
    "ab_len",
    "dg_len",
    "aprt_len",
    "sk_len",
    "gs_len",
    "mops_rules",
    "mops_root0",
    "mops_root1",
    "mops_root2",
    "mops_child_fb",
    "ct_root3",
    "ct_root4",
    "ct_root5",
    "ct_root6",
    "ct_root7",
    "ct_root8",
    "stages",
    "ranges_miss",
    "noopf_n0",
    "noopf_nx",
    "noopf_e_n0",
    "noopf_e_nx",
    "noopf_b4",
    "raf_after_nsrc",
    "raf_after1_is_src0",
    "raf_afterk_none",
    "szs_sh0_is_src0",
    "szs_sh1_is_src0",
    "szs_n0_is_self",
    "nic_calli_ans",
    "nic_calls_ans",
    "nic_callm_ans",
    "nic_b4_ans",
    "nic_calli_nsrc",
    "nic_callm_src0_nsrc",
    "nv_rs_is_src0",
    "nv_rsi_none",
    "nv_b4_none",
    "rb_self_is_noop",
    "rb_self_nsrc",
    "rb_diff_none",
    "rb_e_n0",
    "rb_ixstg_none",
    "aprt_none",
    "aprt_r0t_none",
    "aprt_pglob",
    "aprt_pgloT_none",
    "aprt_palu_none",
    "aprt_paluT_none",
    "aprt_b4_none",
    "ren_untagged_none",
    "ren_arg0",
    "ren_next",
    "ren7_arg0",
    "ren7_next",
    "ren_axis_weak",
    "dg_ixpa_ans",
    "dg_ixpg_none",
    "dg2_pat",
    "dg2_pg",
    "dg2_palu",
    "claim_ops_stg2",
    "claim_ops_stg3",
    "claim_ab_stg2",
    "claim_ab_stg3",
    "ab4_stg2",
    "ab4_stg3",
    "fb_two_stg2",
    "fb_two_stg3",
    "fb_sym_stg3",
    "ab8_sti",
    "ab8_std_none",
    "ab7_cli_nsrc",
    "rej_ct4",
    "rej_ct7",
    "rej_dg3",
    "rej_ab8",
    "raf_aftn_is_src0",
    "ab8_stc0_none",
    "nv_rsaf_ans",
    "dg_r0t_ans",
    "ren_axis_out",
    "ab7_clik_nsrc",
    "ab7_clik_arg",
    "ab7_clik0_arg",
    "nic_clik_nsrc",
    "nic_clik_arg",
    "ct4a_claim",
    "ct4b_claim",
    "ct4a_ans",
    "ct4a_tail",
    "ct4d_tail",
    "ct4d_none",
    "ct5c_claim",
    "ct5k_claim",
    "ct5b_claim",
    "ct5c_pat",
    "ct5k_pat",
    "ct5b_pat",
    "ct5c_ans",
    "ct8d_claim",
    "mstc_claim",
    "ct8d_devnone",
    "ct8b_devnone",
    "ct8d_srcops",
    "ct8r_srcops",
    "ct8d_new",
    "ct8r_arg",
    "ct8r0_arg",
    "ct8r_axis",
    "ct8r0_axis",
    "ct8b_none",
    "ct7a_claim",
    "ct7a_cnt",
    "ct7b_cnt",
    "ct7b_none",
    "ren_axis_out_dev",
    "ren_axis_in_dev",
    "eng_a_r0",
    "eng_a_r1",
    "eng_a_r2",
    "eng_a_r3",
    "eng_a_r4",
    "eng_a_r5",
    "eng_a_r6",
    "eng_b_r0",
    "eng_b_r1",
    "eng_b_r2",
    "eng_b_r3",
    "eng_b_r4",
    "eng_b_r5",
    "eng_b_r6",
    "eng_stages",
    "eng_tables",
    "eng_order",
    "spec",
)

GATE = Gate(
    "gkg-gate",
    bend="tinybendygrad/schedule/rangeify.bend",
    oracle="gates/gkg-oracle.py",
    rows=ROWS,
    compared=COMPARED,
    port_only=PORT_ONLY,
    pins=tuple((lane, row) for lane in ("py", "bd")
               for row in ("eng_a_s3", "eng_b_s3", "eng_a_in", "eng_b_in")),
)

if __name__ == "__main__":
    sys.exit(main(GATE, "gkg-gate: {} rows, {} compared -- `get_kernel_graph`'s SEVEN stages "
                        "(rangeify.py:341-376) over the two fixtures, `op:argkey:srcops` dumps "
                        "stage by stage. 143 rows are port-only and NAMED: the memoisation "
                        "counts, the port's own stage census, and 126 per-rule fixtures that "
                        "have no CPython lane".format(ROWS, COMPARED)))
