#!/usr/bin/env python3
"""dd-split.py -- agree/disagree split between dtype.bend's rows and a fresh dd-oracle.py run,
using rebase-gate.py's OWN rows() so the number is on the gate's parser, not a second one.

  .venv/bin/python .agents/slop/dd-split.py <bend-run.txt> <oracle.txt> [--verbose]

Prints the shared count, the agree count, the disagree count, one line per disagreement,
and a per-family tally keyed on the row-name suffix. Names present on one side only are
reported separately, because a row the parser cannot see is not a disagreement and is
not agreement either.
"""
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rebase_gate_shim import rows  # noqa: E402

FAMILIES = ("lg1n", "lg2k", "lg2n", "lg2p", "lg5k", "lg5n", "lg5sig", "lg6k", "lg6n", "lg6p",
            "lg9k", "lg9n", "lg9p", "lg9sig", "c7")


def family(name):
  """The `lg2p`-style family of a row: the letter+digit stem, or `c7`, or the whole name."""
  m = re.match(r"^(lg[a-z]?[0-9]+)([a-z]*)$", name)
  if m:
    return m.group(1) + m.group(2)
  if re.match(r"^c[0-9]+$", name):
    return name
  return name


def main():
  bend_txt = pathlib.Path(sys.argv[1]).read_text()
  ora_txt = pathlib.Path(sys.argv[2]).read_text()
  verbose = "--verbose" in sys.argv
  b, o = rows(bend_txt), rows(ora_txt)
  shared = set(b) & set(o)
  bad = sorted(k for k in shared if b[k] != o[k])
  only_b = sorted(set(b) - set(o))
  only_o = sorted(set(o) - set(b))
  print(f"bend rows   : {len(b)}")
  print(f"oracle rows : {len(o)}")
  print(f"shared      : {len(shared)}")
  print(f"agree       : {len(shared) - len(bad)}")
  print(f"DISAGREE    : {len(bad)}")
  print(f"only in bend: {len(only_b)}  {' '.join(only_b[:12])}")
  print(f"only in ora : {len(only_o)}  {' '.join(only_o[:12])}")
  by = collections.defaultdict(lambda: [0, 0])
  for k in shared:
    f = by[family(k)]
    f[1] += 1
    if b[k] != o[k]:
      f[0] += 1
  print("\n-- per-family (disagree/total) --")
  for f in sorted(by, key=lambda x: (-by[x][0], x)):
    d, n = by[f]
    if d:
      print(f"  {f:<10} {d}/{n}")
  print("\n-- disagreements --")
  for k in bad:
    if verbose:
      print(f"  {k}\n    bend: {b[k]}\n    ora : {o[k]}")
    else:
      print(f"  {k}\n    bend: {b[k][:150]}\n    ora : {o[k][:150]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())