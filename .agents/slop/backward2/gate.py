#!/usr/bin/env python3
"""THE GATE -- the port's rows against `rows.rows` (CPython's values).

    .venv/bin/python .agents/slop/backward2/gate.py <got.rows> <want.rows>

Prints one line per MISMATCH and a final verdict line.  Exits 0 iff every wanted row
is present and equal.

THE RULE: a wanted row that is ABSENT from the port's output is a MISSING row and
fails, and a wanted row whose value differs is a MISMATCH and fails.  A wanted row
whose value is EMPTY is a MISMATCH too -- an empty expectation is not a weaker check,
it is a check that can only be satisfied by an empty output.
"""
import sys


def load(path):
  rows = {}
  for line in open(path):
    line = line.rstrip("\n")
    if "=" in line:
      k, _, v = line.partition("=")
      rows[k] = v
  return rows


def main():
  got, want = load(sys.argv[1]), load(sys.argv[2])
  bad = []
  for k, v in want.items():
    g = got.get(k)
    if g is None:
      bad.append((k, v, "<MISSING>"))
    elif g != v:
      bad.append((k, v, g))
  for k, v, g in bad:
    print("    MISMATCH %s" % k)
    print("      want: %s" % v)
    print("      got : %s" % g)
  print("    rows compared: %d   mismatched: %d   VERDICT: %s"
        % (len(want), len(bad), "PASS" if not bad else "FAIL"))
  sys.exit(0 if not bad else 1)


main()
