#!/usr/bin/env python3
"""twopass-regress.py -- EVERY corpus graph, one verdict each, DIFFED against the run dir.

DOES NOT COMPARE TWO OF ITS OWN RUNS.  The "before" column is the recorded run directory
`runs/graphcmp/D/D1-graph-<g>.txt`, which is a DIFFERENT PROCESS reading a DIFFERENT tree
state; a harness that diffed its own output against its own output would be green forever.

KEYED ON THE VERDICT TOKEN AND ON `field-mismatches`, NOT ON ROW INDEX and NOT ON LINE
COUNT, because a row-index comparison turns a reordering into a failure and a line count
turns a lost row into a pass.

  .venv/bin/python .agents/slop/twopass/twopass-regress.py
"""
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
RECORDED = REPO / "runs" / "graphcmp" / "D"
OUT = REPO / ".agents" / "slop" / "twopass" / "corpus"
GRAPHS = ("matmul reduce buffer sink range rangeflat cast special binblob group commute "
          "indexed sym lin loop gate bw alu bit where move flip allred cdiv late threefry "
          "mulacc getaddr unshard wmma custom_function mselect mstack stage").split()

# `env -u PYTHONPATH LC_ALL=C DEV=NULL` and NOT a rebuilt PATH: a REBUILT PATH IS WHAT
# MADE THIS LANE DEAD ONCE -- it dropped `bun`, which is what `bin/bend` execs, so all
# 34 graphs printed no verdict at all and the table read "34 MOVED".  A lane that measures
# nothing must NOT be able to print a movement count.
import os

ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
ENV.update({"LC_ALL": "C", "DEV": "NULL"})


def token(text, pat):
  m = re.findall(pat, text)
  return m[-1] if m else "?"


def read(path):
  return path.read_text() if path.exists() else ""


def main():
  OUT.mkdir(parents=True, exist_ok=True)
  moved = []
  print(f"# {'graph':<18} {'before':<9} {'after':<9} {'fm-before':<10} {'fm-after':<9} state")
  for g in GRAPHS:
    before = read(RECORDED / f"D1-graph-{g}.txt")
    dest = OUT / f"{g}.txt"
    with dest.open("w") as fh:
      rc = subprocess.run(
        [str(REPO / ".venv/bin/python"), str(REPO / ".agents/slop/graphcmp.py"),
         "diff", "--graph", g],
        cwd=REPO, stdout=fh, stderr=subprocess.STDOUT,
        env={**ENV}).returncode
    after = read(dest)
    b, a = token(before, r"VERDICT: (\w+)"), token(after, r"VERDICT: (\w+)")
    fb = token(before, r"field-mismatches=(\d+)")
    fa = token(after, r"field-mismatches=(\d+)")
    if not before:
      state = "NO-RECORDED-BEFORE"
    elif a == "?":
      state = "DEAD"
    elif (b, fb) == (a, fa):
      state = "same"
    else:
      state = "MOVED"
      moved.append(g)
    dead = "DEAD" if a == "?" else state
    print(f"{g:<18} {b:<9} {a:<9} {fb:<10} {fa:<9} {dead} rc={rc}")
  print(f"#\n# MOVED {len(moved)}: {moved}")
  disagree_after = [g for g in GRAPHS
                    if token(read(OUT / f'{g}.txt'), r"VERDICT: (\w+)") == "DISAGREE"]
  print(f"# graphs-disagree after: {len(disagree_after)} {disagree_after}")
  return 0


if __name__ == "__main__":
  sys.exit(main())