#!/usr/bin/env python3
# .agents/slop/lane-load.py -- MEASURE A LANE'S ROW COUNT AGAINST MACHINE LOAD.
#
# WHY THIS FILE EXISTS. NV7 (`.agents/slop/notes/bend2-constraints.md`, line 12828) recorded
# that `nvdev.bend`'s interpreted lane went from 787 rows in 0.5 s to 108 rows in 540 s with 19
# `bend` processes resident, and it filed that as a *procedural* inconvenience: "a mutation table
# that runs N compiles needs N x the compile time". That reading treats the row count as a
# property of the FILE. It is a property of the file AND THE RUN QUEUE. The 108 was not a
# smaller graph. It was the same graph, part-way through, in a starved process.
#
# So: a row count with no load beside it is not a count. This tool measures the dependence so
# the threshold, if there is one, is a measured number instead of a story.
#
# THE DESIGN, and why the filler is nice'd AND the lane is nice'd:
#
#   The regime under study is "19 compilers, all at the same priority, some of them lose". Adding
#   NORMAL-priority filler would push other agents' lanes into that regime too -- i.e. it would
#   manufacture starved verdicts in six live units and then be the reason their reports are wrong.
#   So BOTH the filler and the measured lane run at `nice -n 19`. Live agents stay at `nice 0` and
#   keep the CPU; my filler only occupies cores that would otherwise be idle; my lane is the only
#   thing that gets starved, which is precisely the quantity being measured.
#
#   ⚠ THAT MEANS `nice` IS A CONFOUND and cell B below exists to price it. `nice 19` on an idle
#   machine is not the same as `nice 0` on an idle machine, and if B loses rows against A then
#   part of the A..F slope is priority, not load. Reporting A..F without B would be the same
#   error as reporting a disagreement count without a denominator.
#
# ROW COUNTS ARE PRINTED TWICE, because THEY DIFFER:
#   lines=  `wc -l` of stdout. This is the number NV7's 787 and 108 are, so it is the comparable.
#   rows=   rebase-gate.py's `rows()` -- the tool that decides whether a lane is a real lane. A
#           partial lane's tail lines are often `name=mid-fold`, which `rows()` REFUSES as a row
#           (F3: no `=`-free fallback, one-token name). So `lines=` overcounts the starved lane
#           relative to `rows=`, and only `rows=` is what a gate would count. A lane that reports
#           540 lines and 0 rows has produced no claims at all.
#
# ON A TIMEOUT THE PARTIAL OUTPUT IS COUNTED, NOT DISCARDED. The whole point is that a starved
# run prints a PREFIX of the truth: 115 of 787 is not a defect and not a smaller graph, it is a
# run that was still going. Killing it and reporting `rows=0` would be a lie in the opposite
# direction.

import argparse
import hashlib
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")

sys.path.insert(0, os.path.join(ROOT, ".agents", "slop"))
from rebase_gate_shim import rows  # noqa: E402  -- the GATE'S OWN parser, imported not copied


def load1():
  return os.getloadavg()[0]


def resident_bends():
  """How many `bend2/main.ts` processes are resident. This is the variable NV7 actually names
  ("19 `bend` processes resident"), and it is not the same number as the load average: one
  lane at nice 19 on a busy box is one `bend` and a load average of 30."""
  try:
    out = subprocess.run(["pgrep", "-f", "bend2/main.ts"], capture_output=True, text=True)
    return len([l for l in out.stdout.split() if l])
  except OSError:
    return -1


def filler_cmd():
  # A GIL-bound integer recurrence. No allocation after warmup, no syscalls: it exists only to be
  # RUNNABLE, so it adds run-queue depth and nothing else. `sleep` would add depth to nothing.
  return [sys.executable, "-c",
          "x=1\n"
          "while True:\n"
          "    x = (x * 1103515245 + 12345) & 0x7FFFFFFF\n"]


class Fillers:
  """N runnable processes at `nice`. `.start()`/`.stop()` so one Python process can hold a load
  point across several reps -- loadavg decays with a ~60 s time constant, so re-spawning the
  filler per rep would measure the decay as much as the level."""

  def __init__(self, n, nice):
    self.n, self.nice, self.ps = n, nice, []

  def start(self):
    for _ in range(self.n):
      self.ps.append(subprocess.Popen(
          ["nice", "-n", str(self.nice)] + filler_cmd(),
          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    # Let them actually become runnable before the rep starts, or the first rep of a cell is
    # measured against a lower queue than the rest of the cell.
    time.sleep(0.4)

  def stop(self):
    for p in self.ps:
      p.kill()
    for p in self.ps:
      p.wait()
    self.ps = []


def run_once(src, check_only, timeout, lane_nice):
  """(lines, rows, elapsed, rc, timed_out) for ONE run. Partial stdout is counted on timeout."""
  argv = ["nice", "-n", str(lane_nice), BEND, src]
  if check_only:
    argv.append("--check-only")
  t0 = time.monotonic()
  p = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       text=True)
  timed_out = False
  try:
    out, _err = p.communicate(timeout=timeout)
  except subprocess.TimeoutExpired:
    timed_out = True
    p.kill()
    out, _err = p.communicate()
  el = time.monotonic() - t0
  lines = out.count("\n")
  return lines, len(rows(out)), el, p.returncode, timed_out


def md5(path):
  h = hashlib.md5()
  with open(path, "rb") as f:
    h.update(f.read())
  return h.hexdigest()


def main():
  ap = argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--lane", required=True, help=".bend path relative to the repo root")
  ap.add_argument("--fillers", type=int, default=0)
  ap.add_argument("--fillernice", type=int, default=19)
  ap.add_argument("--lanenice", type=int, default=19)
  ap.add_argument("--reps", type=int, default=3)
  ap.add_argument("--timeout", type=float, default=180.0)
  ap.add_argument("--check-only", action="store_true")
  ap.add_argument("--label", default="")
  ap.add_argument("--out", default="")
  args = ap.parse_args()

  src = args.lane if os.path.isabs(args.lane) else os.path.join(ROOT, args.lane)
  if not os.path.exists(src):
    print(f"NO SUCH LANE: {src}", file=sys.stderr)
    return 2
  label = args.label or (f"fillers={args.fillers} nice={args.lanenice}"
                         + (" check-only" if args.check_only else ""))
  print(f"# LANE {os.path.relpath(src, ROOT)}  md5={md5(src)}  {label}")
  print(f"# header  cell  rep  load1_start  n_bends  lines  rows  secs  rc  timed_out")
  recs = []
  fil = Fillers(args.fillers, args.fillernice)
  fil.start()
  for rep in range(1, args.reps + 1):
    l0, nb = load1(), resident_bends()
    lines, nrows, el, rc, to = run_once(src, args.check_only, args.timeout, args.lanenice)
    print(f"{label}\t{rep}\t{l0:.2f}\t{nb}\t{lines}\t{nrows}\t{el:.2f}\t{rc}\t{int(to)}",
          flush=True)
    recs.append((rep, l0, nb, lines, nrows, el, rc, to))
  fil.stop()
  print(f"# {label}: load1_end={load1():.2f} n_bends_end={resident_bends()} "
        f"src_md5_end={md5(src)}  reps={args.reps}")
  print(f"# rows: {[r[4] for r in recs]}  lines: {[r[3] for r in recs]}  "
        f"secs: {[round(r[5], 2) for r in recs]}", flush=True)
  if args.out:
    with open(os.path.join(ROOT, args.out), "a") as f:
      f.write(f"# CELL {label} lane={os.path.relpath(src, ROOT)} md5={md5(src)} "
              f"fillernice={args.fillernice} lanenice={args.lanenice} "
              f"timeout={args.timeout} reps={args.reps}\n")
      for rep, l0, nb, lines, nrows, el, rc, to in recs:
        f.write(f"{label}\t{rep}\t{l0:.2f}\t{nb}\t{lines}\t{nrows}\t{el:.2f}\t{rc}\t{int(to)}\n")
    print(f"# appended {args.out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
