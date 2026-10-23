#!/usr/bin/env python3
"""cmppins.py -- THE CONTROL, and the two attribution readings.

    .venv/bin/python .agents/slop/randcensus/cmppins.py

1. THE CONTROL: the NEW pin is NOT satisfied by the OLD output, and the OLD pin is NOT
   satisfied by the NEW output.  A pin that both answers would be a pin that cannot fail.
2. THE ATTRIBUTION: the four `st_*_g` rows, read at FOUR points of the tree's history --
   `1af4ba921^` (before the size->src[0] migration), the LIVE tree, the live tree with the
   2026-10-23 `mixin/rand.bend` fix REVERTED, and the live tree with the ALLOC's `src[0]`
   removed.  Each is matched against the OLD pin and the NEW pin.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRATCH = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/randcensus")
sys.path.insert(0, str(ROOT / "gates"))

_spec = importlib.util.spec_from_file_location("rand_census_gate", ROOT / "gates" / "rand_census-gate.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
DIVERGES = _mod.DIVERGES

# THE OLD PORT PINS, AS THE GATE CARRIED THEM AT HEAD `13fbb54fe5b0bdbceed52fe9c76d8d5d0e7f8e06`.
OLD_PORT = {
  "st_zero_g": ("st_zero_g=26 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 SHRINK/3 CONST/0 ADD/2 "
                "SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
                "RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_six_g": ("st_six_g=27 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 SHRINK/3 "
               "ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
               "RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_after_g": ("st_after_g=47 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 "
                 "SHRINK/3 ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 "
                 "SHRINK/3 RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2 SHRINK/3 "
                 "CAST/1 ADD/2 SHRINK/3 CAST/1 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 STACK/2 RESHAPE/2 SHRINK/3 "
                 "RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_max_g": ("st_max_g=24 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 SHRINK/3 "
               "ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
               "RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
}

# THE NEW PORT PINS -- read off the LIVE lane.
LIVE = {}
for l in (ROOT / ".agents/slop/randcensus/bd.out").read_text().splitlines():
  if "=" in l:
    LIVE[l.split("=", 1)[0]] = l
NEW_PORT = {k: LIVE[k] for k in OLD_PORT}

LANES = {
  "1af4ba921^ (pre sizetosrc)": SCRATCH / "pre.out",
  "LIVE (2026-10-23 fix in)": ROOT / ".agents/slop/randcensus/bd.out",
  "LIVE with the 2026-10-23 fix REVERTED": SCRATCH / "revfix.out",
  "LIVE with the ALLOC's src[0] REMOVED": SCRATCH / "revalloc.out",
}

print("== 1. THE CONTROL: does either pin satisfy the other lane?")
print("   (a pin that BOTH answers is a pin that cannot fail)")
for k in OLD_PORT:
  old, new = OLD_PORT[k], NEW_PORT[k]
  print(f"  {k}: new-pin-in-old-output={new in OLD_PORT[k]}  old-pin-in-new-output={old in NEW_PORT[k]}")
print()

print("== 2. THE ATTRIBUTION: which lane answers which pin?")
for label, path in LANES.items():
  rows = {}
  for l in path.read_text().splitlines():
    if "=" in l:
      rows[l.split("=", 1)[0]] = l
  olds = sum(1 for k in OLD_PORT if OLD_PORT[k] in rows.get(k, ""))
  news = sum(1 for k in NEW_PORT if NEW_PORT[k] in rows.get(k, ""))
  fold = rows.get("fold_np", "<absent>").split("=", 1)[1]
  fold5 = rows.get("fold5_np", "<absent>").split("=", 1)[1]
  print(f"  {label:<42} old-pin {olds} of 4   new-pin {news} of 4   fold_np={fold}  fold5_np={fold5}")
