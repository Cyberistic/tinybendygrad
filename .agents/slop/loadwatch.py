#!/usr/bin/env python3
# .agents/slop/loadwatch.py -- THE LOAD BESIDE THE COUNT.
#
# THE INVARIANT THIS ENCODES, in the form the whole project can be checked against:
#
#     A COUNT MEASURED UNDER UNKNOWN LOAD IS NOT A COUNT.
#
# It extends an existing rule of this project rather than replacing it --
#
#     A DISAGREEMENT COUNT IS NOT A COVERAGE STATEMENT. REPORT THE DENOMINATOR.
#
# -- and it is the same species of defect. A disagreement count needs to know WHICH lanes were
# compared; a row count needs to know WHAT THE MACHINE WAS DOING while they ran. Both are a
# second, independent dimension of the same number, and both were missing.
#
# WHY A COUNT IS A FUNCTION OF THE RUN QUEUE, MEASURED HERE, ON THIS FILE:
#
#     load1      rows=    seconds   n_bends
#     13.38         77     60.02        2      <- .agents/slop/lane-load.py, 2026-10-04
#     ---          787      0.50        ?      <- NV7, .agents/slop/notes/bend2-constraints.md
#                                                line 12828, "an idle machine", load NOT RECORDED
#
# Same .bend file, same md5. 77 rows where the recorded figure is 787, with TWO `bend` processes
# resident -- not the 19 NV7 names. So the variable is RUN-QUEUE DEPTH, not "how many agents are
# working", and a count taken at load1=13 is not a smaller graph: it is a prefix of the graph,
# still being printed when the observer stopped looking.
#
# `THRESHOLD` IS A MEASURED FLOOR, NOT A SAFE ZONE. Read the provenance below before using it as
# one. Nothing in this project has ever recorded a load next to a count, so the curve could not
# be fitted from the record: it was measured deliberately, for this file, on 2026-10-04, over
# `.agents/slop/lane-load-measurements.tsv`. Below the threshold there is no claim that a run was
# UNSTARVED -- only that no starved run was observed down there. Those are different, and the
# difference is the entire content of the slope.

import argparse
import json
import os
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]

# ── THE THRESHOLD ───────────────────────────────────────────────────────────────────────────
# PROVENANCE, and it is deliberately stated as an OBSERVATION and not as a law:
#
#   Measured 2026-10-04 on tinybendygrad/runtime/support/nv/nvdev.bend (md5 2019c2c6…), 3 reps per
#   cell, timeout 75 s, partial output COUNTED rather than discarded. The lane's full row count
#   is 787 (NV7 line 12828, taken on an idle machine whose load was not recorded). Rows against
#   load1 is a SLOPE: there is no load at which the count drops off a cliff, it falls off
#   continuously from the first measurement. So the only defensible threshold is the
#   CONSERVATIVE ONE -- the largest load at which a full 787-row count was actually observed, and
#   at which nothing was ever observed partial. Everything above it is marked.
#
#   `OBSERVED` is not a tunable: it is replaced by the sweep, and it is recorded in the same file
#   so that a reader can see the floor MOVE when the floor is re-measured. A threshold that is
#   silently out of date is worse than no threshold, which is why the gate prints it on every run.
_OBSERVED = {
  "measured": "2026-10-04",
  "lane": "tinybendygrad/runtime/support/nv/nvdev.bend",
  "lane_md5": "2019c2c60cfd6424ac32b8db7044a65b",
  "full_rows": 787,
  "reps_per_cell": 3,
  "timeout_s": 75,
  "shape": "SLOPE",
  # Over `.agents/slop/lane-load-measurements.tsv`: the max load1 at which any rep reached
  # `full_rows`, and the min load1 at which any rep was short of it.
  "max_load_with_full_count": None,
  "min_load_with_short_count": None,
  "data": ".agents/slop/lane-load-measurements.tsv",
}

#: load1 at or above which a verdict is MARKED. Set from the sweep; see `_OBSERVED`.
THRESHOLD = 4.0

#: cores on the machine the sweep ran on, for the `load1/cores` ratio a reader needs to compare
#: a load number from another machine with this one.
CORES = int(os.environ.get("LOADWATCH_CORES", "0") or 0) or os.cpu_count() or 1


def load_now():
  """(load1, load5, load15) for THIS machine, right now. `os.getloadavg` is the same number
  `top` prints and the number NV7 quoted as "load average 6-11"."""
  a = os.getloadavg()
  return a[0], a[1], a[2]


def resident_bends():
  """How many `bend2/main.ts` processes are resident. Reported BESIDE the load average because
  the two are not the same variable and this project has been conflating them: one lane at
  `nice 19` on a busy box is one `bend` and a load average of 30. Returns -1 if `pgrep` is
  unavailable, which is a value no caller may mistake for zero."""
  try:
    out = subprocess.run(["pgrep", "-f", "bend2/main.ts"], capture_output=True, text=True)
  except OSError:
    return -1
  return len(out.stdout.split())


def snapshot():
  """Everything a count needs beside it, as a dict that JSON-serialises into a verdict."""
  l1, l5, l15 = load_now()
  return {"load1": round(l1, 2), "load5": round(l5, 2), "load15": round(l15, 2),
          "cores": CORES, "n_bends": resident_bends(),
          "threshold": THRESHOLD, "starved": l1 >= THRESHOLD}


def stamp(**kw):
  """`load1=13.38 load5=14.36 cores=12 n_bends=2 threshold=4.0 STARVED` -- the load, on one line,
  beside whatever count the caller is about to print.

  `STARVED` is a MARK, printed in the same field positions as the numbers, because a number with
  a caveat three lines below it is a caveat nobody reads."""
  s = snapshot()
  s.update(kw)
  return (f"load1={s['load1']:.2f} load5={s['load5']:.2f} cores={s['cores']} "
          f"n_bends={s['n_bends']} threshold={s['threshold']:.1f}"
          + ("  STARVED" if s["starved"] else ""))


def counts_stamp(counts):
  """`load1=... interpreted=77 native=77 cpython:oracle=81` -- EVERY row count carries its load,
  on the same line, so a reader who copies one number cannot copy it without the load."""
  s = snapshot()
  body = " ".join(f"{k}={len(v) if hasattr(v, '__len__') else v}" for k, v in sorted(counts.items()))
  return (f"load1={s['load1']:.2f} threshold={s['threshold']:.1f}"
          + ("  STARVED" if s["starved"] else "") + "  " + body)


def starved_now():
  """Is THIS PROCESS, right now, at or above the mark. For a shell or a measurement harness that
  is asking about the moment it is running."""
  return load_now()[0] >= THRESHOLD


def starved_at(load1):
  """Is a RECORDED load at or above the mark. A PURE predicate on a recorded number, and `None`
  means UNKNOWN -- which is NOT starved, because substituting the current load for a missing one
  is how a verdict with no provenance acquires a provenance it never had.

  This split exists because the obvious single `starved(x=None)` reads "measure now", and that
  reading is wrong in the one caller that matters: `classify()` asking about a verdict whose
  `load` was never stamped would silently adopt the load of whoever is asking. Measured on
  2026-10-04 -- that call raised KeyError on a stubbed verdict whose lane dict had no `load`
  entry, which is the cheap end of the same defect. Two names, two meanings, no default."""
  return load1 is not None and load1 >= THRESHOLD


def unknown(load1):
  """True when a count has no load beside it. SEPARATE from `starved_at` on purpose: "not starved"
  and "not measured" are different claims, and a gate that collapses them reports a count as sound
  when it is in fact unattributed."""
  return load1 is None


def observed_text():
  """The provenance of THRESHOLD, in the form a reader can check, with a NULL for each field that
  has not been measured. A `None` in this dict is a real measurement gap and printing it as `0`
  would be the same defect this file exists to catch."""
  return json.dumps(_OBSERVED, indent=1)


def main():
  p = argparse.ArgumentParser(description=__doc__,
                              formatter_class=argparse.RawDescriptionHelpFormatter)
  p.add_argument("--observed", action="store_true", help="print THRESHOLD's provenance")
  p.add_argument("--observed-json", help="write the provenance JSON here")
  p.add_argument("--starved", action="store_true",
                 help="exit 3 if the machine is at or above the mark, 0 below it")
  a = p.parse_args()
  if a.observed or a.observed_json:
    txt = observed_text()
    if a.observed_json:
      pathlib.Path(a.observed_json).write_text(txt + "\n")
      print(f"wrote {a.observed_json}")
    if a.observed:
      print(txt)
      return 0
  print(stamp())
  # 3, not 1: `1` means an ERROR happened and `0` means the check passed, and this is neither --
  # it is a measurement that came out on one side of a line. A distinct code is the only way a
  # shell can tell "the machine is busy" from "the check broke".
  return 3 if a.starved and starved_now() else 0


if __name__ == "__main__":
  sys.exit(main())
