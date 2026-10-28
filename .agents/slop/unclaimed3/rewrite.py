"""A THROW-AWAY LINE-NEUTRAL REWRITER.

A pointer's line number is a fact about the tree, and a comment edit that MOVES
lines moves every pointer into the file. This replaces a run of lines with a run
of the SAME LENGTH, so the file's line numbers do not move and the pointers into
it keep pointing at what they pointed at.

Usage: `rewrite.py <file> <start-line> <old-line-count> <new-file>` where
`new-file` holds the replacement lines.
"""
import sys
from pathlib import Path

path = Path(sys.argv[1])
start = int(sys.argv[2])
count = int(sys.argv[3])
new = Path(sys.argv[4]).read_text().rstrip("\n").split("\n")
lines = path.read_text().split("\n")
old = lines[start - 1:start - 1 + count]
if len(new) != count:
  sys.exit(f"the replacement is {len(new)} lines and the run is {count}: REFUSED")
lines[start - 1:start - 1 + count] = new
path.write_text("\n".join(lines))
print(f"{path}: {count} lines at :{start} replaced, line numbers unchanged")
