#!/usr/bin/env python3
"""**THE **WIRE's **NUMBER **LIST**, **BYTE **FOR **BYTE**, **BETWEEN **TWO **BUILDS** -- **⇒⇒† AND **AND
**THE **WIRE **IS **THE **PORT's **OWN **PROTOCOL**, **⇒⇒† AND **AND **A **CHANGE **TO **IT **THAT
**CHANGES **A **NUMBER **IS **A **CORRECTNESS **DEFECT**, **⇒⇒† AND **AND **NOT **A **PERFORMANCE
**ONE**.

**⇒⇒† AND **THE **COMPARISON **IS **OVER **THE **WIRE's **OWN **EFFECT** (⇒⇒† AND **AND **THE **SAME
**ONE **THE **PORT **CALLS**)**.
"""

import json
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def wire_of(path: pathlib.Path, tag: str) -> str:
  """THE **WIRE's **NUMBER **LIST**, **AS **THE **DAEMON **HANDLES **IT**."""
  d = noisefloor.Daemon(path, tag)
  d.start()
  time.sleep(0.8)
  d.turn()
  time.sleep(0.2)
  d.stop()
  p = pathlib.Path(str(d.cpu_file) + ".wi")
  return p.read_text() if p.exists() else ""


def main():
  a = BUILD / (sys.argv[1] if len(sys.argv) > 1 else "serve_plus.js")
  b = BUILD / (sys.argv[2] if len(sys.argv) > 2 else "serve_wire_new.js")
  wa = wire_of(a, "wia")
  wb = wire_of(b, "wib")
  print()
  print("THE **WIRE's **NUMBERS**:")
  print("  A (%s): %d bytes" % (a.name, len(wa)))
  print("  B (%s): %d bytes" % (b.name, len(wb)))
  print("  **THE **NUMBERS **ARE **IDENTICAL**" if wa == wb else "  **THE **NUMBERS **DIFFER**")
  if wa != wb:
    for i, (x, y) in enumerate(zip(wa, wb)):
      if x != y:
        print("  the first difference at %d: %r vs %r" % (i, wa[max(0, i - 80):i + 80],
                                                        wb[max(0, i - 80):i + 80]))
        break


if __name__ == "__main__":
  main()
