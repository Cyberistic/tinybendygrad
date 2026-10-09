#!/usr/bin/env python
"""probe_srccount.py -- SRC COUNT OF EVERY HAND-BUILT `OpsGROUP{}` IN graphcmp.bend.

WHY THIS EXISTS: `tinygrad/uop/ops.py:559` short-circuits `UOp.group` of ONE src to the
src itself, so a single-src GROUP is a node upstream NEVER builds. If exactly one of the
twelve hand-built GROUPs has one src, that is the fixture's defect and the other eleven
are not.

FIRST ATTEMPT WAS WRONG, and wrong in the direction that hides a finding: it counted
`O\.Found\.i\(` only on the line carrying `OpsGROUP{}`, so the four statements that WRAP
onto a second line read 0 srcs. It also tracked bracket depth as a running delta over a
concatenated statement, which double-counts, and ran off the end of the file
(IndexError). Here each statement is read from its `OpsGROUP{}` until brackets BALANCE.
"""
import pathlib, re
bend = pathlib.Path(".agents/slop/graphcmp.bend").read_text().splitlines()
defs = [i for i, l in enumerate(bend) if l.startswith("def ")]
out = []
for i, ln in enumerate(bend):
  if "OpsGROUP{}" not in ln:
    continue
  j, stmt = i, ""
  while True:  # read forward until the statement's brackets balance
    stmt += " " + bend[j].strip()
    if stmt.count("[") == stmt.count("]"):
      break
    j += 1
    assert j < len(bend), f"unbalanced OpsGROUP statement at line {i+1}"
  srcs = re.findall(r"O\.Found\.i\(", stmt)
  owner = max(d for d in defs if d < i)
  out.append((i + 1, bend[owner].split("(")[0][4:], len(srcs)))
print(f"{'line':>6}  {'graph':<10} {'srcs':>4}   tinygrad/uop/ops.py:559 says")
for ln, name, n in out:
  print(f"{ln:>6}  {name:<10} {n:>4}   " + ("IDENTITY -- upstream makes NO GROUP node" if n == 1 else "GROUP node"))
one = [l for l, _, n in out if n == 1]
print()
print(f"OpsGROUP statements in graphcmp.bend : {len(out)}")
print(f"  with >=2 srcs (upstream makes one) : {len(out)-len(one)}")
print(f"  with EXACTLY 1 src (upstream makes NONE): {one}")
