#!/usr/bin/env python3
"""Add RAW probe rows to `multi.bend` in the measurement copy. Idempotent-safe: refuses
if they are already present, so the BEFORE and AFTER runs are instrumented IDENTICALLY
and the pair is comparable."""

import re
import sys
from pathlib import Path

MULTI = Path("tinybendygrad/schedule/multi.bend")

DEFS = """
# ==== RAW PROBE ROWS (measurement copy only; not part of the port) ====
def r_own_n() -> U32: mt_n(mu_own())
def r_ra_n() -> U32: mt_n(mu_ra_base())
def r_pm_n() -> U32: mt_n(mu_table(mu_c_early()))
def r_late_n() -> U32: mt_n(mu_table(mu_c_late()))
def r_rej_n() -> U32: mt_rej_n(mu_table(mu_c_early()))
def r_rej_late() -> U32: mt_rej_n(mu_table(mu_c_late()))
def r_ops_n() -> U32: mt_ops_n(mu_table(mu_c_early()))
def r_mov_n() -> U32: mt_ops_n([O.PMEntry{23, mu_move_ops(), mu_rej_nil()}])
def r_e19() -> U32: mt_op(mu_table(mu_c_early()), 19n)
def r_e20() -> U32: mt_op(mu_table(mu_c_early()), 20n)
def r_l19() -> U32: mt_op(mu_table(mu_c_late()), 19n)
def r_l20() -> U32: mt_op(mu_table(mu_c_late()), 20n)
def r_l23() -> U32: mt_op(mu_table(mu_c_late()), 23n)
def r_l24() -> U32: mt_op(mu_table(mu_c_late()), 24n)
def r_l25() -> U32: mt_op(mu_table(mu_c_late()), 25n)
def r_te19() -> U32: mt_tag(mu_table(mu_c_early()), 19n)
def r_tl25() -> U32: mt_tag(mu_table(mu_c_late()), 25n)
def r_full_su() -> U32: mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_su(g()))
def r_full_st() -> U32: mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_st(g()))
def r_first_st() -> U32: mu_first(mu_table(mu_c_early()), G.ar(g()), g_st(g()))
def r_first_su() -> U32: mu_first(mu_table(mu_c_early()), G.ar(g()), g_su(g()))
def r_first_ad() -> U32: mu_first(mu_table(mu_c_early()), G.ar(g()), g_ad(g()))
def r_first_m0() -> U32: mu_first(mu_table(mu_c_early()), G.ar(g()), g_m0(g()))
def r_claim_su() -> U32: mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_su(g()))
def r_claim_st() -> U32: mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_st(g()))
"""

NAMES = ["r_own_n", "r_ra_n", "r_pm_n", "r_late_n", "r_rej_n", "r_rej_late", "r_ops_n",
         "r_mov_n", "r_e19", "r_e20", "r_l19", "r_l20", "r_l23", "r_l24", "r_l25",
         "r_te19", "r_tl25", "r_full_su", "r_full_st", "r_first_st", "r_first_su",
         "r_first_ad", "r_first_m0", "r_claim_su", "r_claim_st"]


def main() -> int:
  src = MULTI.read_text()
  if "r_own_n" in src:
    sys.exit("the probe rows are already present; refusing to double them")
  anchor = "# THE INVENTORY COUNTS."
  if src.count(anchor) != 1:
    sys.exit(f"the def anchor appears {src.count(anchor)} times")
  src = src.replace(anchor, DEFS.lstrip("\n") + "\n" + anchor, 1)

  main_anchor = '    _ : Unit <- row("t_rw", t_rw())'
  if src.count(main_anchor) != 1:
    sys.exit("the main() anchor is not unique")
  rows = "".join(f'    _ : Unit <- row("{n}", {n}())\n' for n in NAMES)
  src = src.replace(main_anchor, main_anchor + "\n" + rows.rstrip("\n"), 1)
  MULTI.write_text(src)
  print(f"added {len(NAMES)} probe rows")
  return 0


if __name__ == "__main__":
  sys.exit(main())