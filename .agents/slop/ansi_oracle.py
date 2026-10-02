#!/usr/bin/env python3
"""CPython lane of the `ansistrip` gate. Every expectation is PRODUCED BY
CALLING `tinygrad.helpers.ansistrip` -- which is `re.sub('\\x1b\\[(K|.*?m)', '', s)`
at helpers.py:48 -- on the fixtures in `ansi_fixture.py`. Nothing is transcribed.

    .venv/bin/python .agents/slop/ansi_oracle.py > .agents/slop/ansi_oracle.txt

Prints ONE `name=value` line per fixture, `name` is the fixture INDEX, and the
value is the fixture's bytes rendered so a terminal cannot eat them: every byte
below 0x20 and 0x7f becomes `<XX>` with uppercase hex, and everything else is
passed through. The Bend lane renders identically, so the diff is over whole
lines and never over row NAMES.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ansi_fixture import FIXTURES  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO)
from tinygrad.helpers import ansistrip  # noqa: E402


def render(s):
  out = []
  for ch in s:
    o = ord(ch)
    out.append("<%02X>" % o if o < 0x20 or o == 0x7F else ch)
  return "".join(out)


def main():
  if len(FIXTURES) < 30:
    sys.exit("fixture list is %d long -- it must be non-uniform" % len(FIXTURES))
  print("# rows %d" % len(FIXTURES))
  for i, fx in enumerate(FIXTURES):
    print("ansi_%02d=%s" % (i, render(ansistrip(fx))))


if __name__ == "__main__":
  main()
