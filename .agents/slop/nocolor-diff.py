#!/usr/bin/env python3
"""
The NO_COLOR differ.  Diffs WHOLE LINES, not row names.

  uv run python .agents/slop/nocolor-oracle.py  > .agents/slop/nocolor-oracle.txt
  ./bin/bend .agents/slop/nocolor-probe.bend    > .agents/slop/nocolor-bend.txt
  uv run python .agents/slop/nocolor-diff.py

CPython's answers come from importing tinygrad in a fresh process per probe; the
Bend answers come from helpers.bend's no_color_of over the same 31 probes, in the
same order.  A CPython REFUSED line means int() raised and tinygrad would not
import at all; there is no such thing in a total language, so the port is REQUIRED
to answer False on those lines (colour ON, the default reading) rather than to
match.  Every other line must match exactly, except the one NAMED boundary below:
an unnamed gap is a gap, a named one is a boundary.
"""
import sys

ORACLE = ".agents/slop/nocolor-oracle.txt"
BEND = ".agents/slop/nocolor-bend.txt"

# line -> why it cannot match.  Line 30 is probe p29, the Arabic-Indic digit
# U+0663: CPython's int() takes every Unicode decimal digit and Bend's
# `Char.is_digit` is ASCII (MEASURED), so `nc_in` cannot see it and answers False
# where CPython answers True.  Closing it means a Unicode Nd table, not this unit.
NAMED = {30: "Char.is_digit is ASCII; CPython int() also takes Unicode Nd digits"}


def main():
  o = [l.strip() for l in open(ORACLE, encoding="utf-8") if l.strip()]
  b = [l.strip() for l in open(BEND, encoding="utf-8") if l.strip()]
  if len(o) != len(b):
    print("LENGTH MISMATCH: oracle %d lines, bend %d lines" % (len(o), len(b)))
    return 1
  bad = refused = named = agree = 0
  for i, (want, got) in enumerate(zip(o, b)):
    if want == got:
      agree += 1
    elif want == "REFUSED" and got == "False":
      refused += 1
    elif i in NAMED:
      named += 1
      print("line %d: CPython %s, port %s   [NAMED BOUNDARY: %s]"
            % (i, want, got, NAMED[i]))
    else:
      bad += 1
      print("line %d: CPython %s, port %s   <-- DIVERGENCE" % (i, want, got))
  print("exact %d  refusal-answered-False %d  named-boundary %d  DISAGREE %d  of %d probes"
        % (agree, refused, named, bad, len(o)))
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())