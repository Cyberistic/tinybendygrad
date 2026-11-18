#!/usr/bin/env python3
"""**THE **HAND **EDIT** -- **REPLACE **A **LINE **RANGE **OF **A **`.bend` **FILE **WITH **TEXT**, **AND
**IT **REFUSES **IF **A **NON-`#` **LINE **MOVED**.

**⇒⇒† AND **IT **IS **THE **SAME **SAFETY **PROPERTY **AS **`cut.py`**, **⇒⇒† AND **IT **IS **HERE **SO
**THE **HAND **FIXES **AND **THE **MECHANICAL **CUT **ARE **GUARDED **THE **SAME **WAY**."""
import pathlib
import sys


def main() -> int:
  path = pathlib.Path(sys.argv[1])
  first = int(sys.argv[2])  # 1-based, inclusive
  last = int(sys.argv[3])   # 1-based, inclusive
  repl_file = pathlib.Path(sys.argv[4])
  text = path.read_text()
  lines = text.split("\n")
  repl = repl_file.read_text().split("\n")
  if repl and repl[-1] == "":
    repl = repl[:-1]
  out = lines[:first - 1] + repl + lines[last:]
  new = "\n".join(out)
  oldcode = [l for l in lines if not l.strip().startswith("#")]
  newcode = [l for l in new.split("\n") if not l.strip().startswith("#")]
  if newcode != oldcode:
    import difflib
    print("REFUSED: a NON-COMMENT LINE MOVED", file=sys.stderr)
    for l in list(difflib.unified_diff(oldcode, newcode, "old", "new", lineterm=""))[:40]:
      print(l, file=sys.stderr)
    return 1
  path.write_text(new)
  print(f"OK {path}: lines {first}-{last} -> {len(repl)} lines, {len(oldcode)} code lines UNCHANGED")
  return 0


if __name__ == "__main__":
  sys.exit(main())
