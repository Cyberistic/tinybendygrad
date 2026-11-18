#!/usr/bin/env python3
"""**THE **COMMENT **SURGERY **TOOL**, **ADDRESSED **BY **BLOCK **ORDINAL**.

**⇒⇒† AND **IT **EDITS **COMMENTS **ONLY**: **EVERY **NON-`#` **LINE **IS **CHECKED **AGAINST **THE
**ORIGINAL**, **⇒⇒† AND **THE **TOOL **REFUSES **TO **WRITE **IF **ONE **MOVED**.

**⇒⇒† AND **WHY **AN **ORDINAL **AND **NOT **AN **ANCHOR**: **A **FILE **MAY **HOLD **THE **SAME
**COMMENT **BLOCK **TWICE** -- **MEASURED, `uop/fold.bend` **HELD **THE **FP8 **BLOCK **TWICE **AND
**`uop/render.bend` **HELD **A **`uops_index` **LINE **FOUR **TIMES**, **⇒⇒† AND **NO **PREFIX **OF **A
**LINE **THEN **IDENTIFIES **ONE **BLOCK**, **⇒⇒† AND **AN **ORDINAL **IS **THE **BLOCK's **POSITION
**IN **THE **FILE's **BLOCK **SEQUENCE **AND **IS **UNAMBIGUOUS **BY **CONSTRUCTION**.

**USAGE**: `cut-by-ordinal.py <file.bend> <ops.json>` **WHERE **THE **OPS **FILE **IS **A **JSON
**LIST**: `[[<ordinal>, "<replacement text>"], ...]` **AND **THE **REPLACEMENT **MAY **BE **THE **EMPTY
**STRING**, **WHICH **DELETES **THE **WHOLE **BLOCK**.
"""
import json
import pathlib
import sys


def blocks_of(lines):
  """**THE **BLOCKS**: **A **RUN **OF **CONTIGUOUS **COMMENT **LINES**, **AS **PAIRS **OF
  **0-BASED **[START, END) **LINE **INDEXES**."""
  out = []
  i = 0
  while i < len(lines):
    if lines[i].strip().startswith("#"):
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"):
        j += 1
      out.append((i, j))
      i = j
    else:
      i += 1
  return out


def main() -> int:
  path = pathlib.Path(sys.argv[1])
  ops = json.loads(pathlib.Path(sys.argv[2]).read_text())
  lines = path.read_text().split("\n")
  blocks = blocks_of(lines)
  code = [l for l in lines if not l.strip().startswith("#")]
  edits = []
  for op in ops:
    ordinal, repl = op[0], op[1]
    if not isinstance(ordinal, int) or not 0 <= ordinal < len(blocks):
      print(f"REFUSED: ordinal {ordinal} is not a block of {path} ({len(blocks)} blocks)", file=sys.stderr)
      return 1
    edits.append((blocks[ordinal][0], blocks[ordinal][1], repl))
  edits.sort()
  out = []
  pos = 0
  for i, j, repl in edits:
    if i < pos:
      print("REFUSED: two ops address overlapping blocks", file=sys.stderr)
      return 1
    out.extend(lines[pos:i])
    if repl:
      out.extend(repl.split("\n"))
    pos = j
  out.extend(lines[pos:])
  new = "\n".join(out)
  newcode = [l for l in new.split("\n") if not l.strip().startswith("#")]
  if newcode != code:
    print("REFUSED: a NON-COMMENT LINE MOVED", file=sys.stderr)
    import difflib
    for l in list(difflib.unified_diff(code, newcode, "old", "new", lineterm=""))[:40]:
      print(l, file=sys.stderr)
    return 1
  path.write_text(new)
  print(f"OK {path}: {len(ops)} blocks edited, {len(code)} code lines UNCHANGED")
  return 0


if __name__ == "__main__":
  sys.exit(main())
