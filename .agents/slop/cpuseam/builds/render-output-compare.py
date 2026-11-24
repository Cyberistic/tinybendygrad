#!/usr/bin/env python3
"""**THE **RENDER's **OUTPUT**, **BYTE **FOR **BYTE**, **BETWEEN **TWO **BUILDS** -- **⇒⇒† AND **AND
**THE **OUTPUT **IS **THE **CORPUS's **SUBJECT**, **⇒⇒† AND **AND **THE **GATE **IS **THE **STRONGER
**CHECK**.

**WHY.** **A **PERFORMANCE **CHANGE **THAT **CHANGES **THE **TEXT **IS **NOT **A **PERFORMANCE
**CHANGE** (⇒⇒† AND **AND **THE **TREE's OWN RULE**: **THE **CORPUS **COMPARES **THE **BYTES**)**.
**⇒⇒† AND **AND **THE **RENDER's **OUTPUT **IS **A **STRING**, **⇒⇒† AND **AND **SO **THE **TWO
**BUILDS' **OUTPUT **CAN **BE **COMPARED **DIRECTLY**.

**⇒⇒† AND **THE **COMPARISON **IS **OVER **THE **DAEMON's **OWN **PRINTED **RENDER** (⇒⇒† AND **AND
**NOT **OVER **A **FILE**, **⇒⇒† AND **AND **SO **IT **IS **THE **SAME **BYTES **THE **CORPUS
**SEES**)**
"""

import pathlib
import re
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def render_of(path: pathlib.Path) -> str:
  """THE **RENDER's **TEXT**, **AS **THE **DAEMON **PRINTS **IT**."""
  d = noisefloor.Daemon(path, "cmpout")
  d.start()
  time.sleep(0.8)
  out = d.turn()
  time.sleep(0.2)
  d.stop()
  return out


def main():
  a = BUILD / (sys.argv[1] if len(sys.argv) > 1 else "serve_base.js")
  b = BUILD / (sys.argv[2] if len(sys.argv) > 2 else "serve_plus.js")
  ra = render_of(a)
  rb = render_of(b)
  print()
  print("THE **RENDER's **OUTPUT**:")
  print("  A (%s): %d bytes" % (a.name, len(ra)))
  print("  B (%s): %d bytes" % (b.name, len(rb)))
  if ra == rb:
    print("  **THE **OUTPUT **IS **BYTE-IDENTICAL**")
  else:
    print("  **THE **OUTPUT **DIFFERS**")
    for i, (x, y) in enumerate(zip(ra, rb)):
      if x != y:
        print("  the first difference at %d: %r vs %r" % (i, ra[max(0, i - 60):i + 60],
                                                        rb[max(0, i - 60):i + 60]))
        break
    else:
        print("  the shorter one ends at %d" % min(len(ra), len(rb)))


if __name__ == "__main__":
  main()
