#!/usr/bin/env python3
"""measure3.py -- the remaining numbers: the 22-vs-37 discrepancy, the shipped reader's
key counts, and the rebase-gate baseline lane.

READ-ONLY.  Uses the gate's own imported readers and the tree's own `rebase-gate.py`.
"""
import importlib.util
import json
import pathlib

REPO = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("rn_gate", REPO / "checks" / "rn-gate.py")
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)

CAND = REPO / "oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows"
FLIP = REPO / ".agents/slop/flipthird/base-render.err"

port = "".join(FLIP.read_text().splitlines(keepends=True)[21:161])
orc = CAND.read_text()

print("=" * 78)
print("THE 22: WHICH OF THE ORACLE'S 80 ROWS CARRY ']   py=[' AND HOW MANY PHYSICAL LINES")
print("=" * 78)
sep_rows = [(lg[0], lg[1], lg[2]) for lg in G.logical_rows(orc) if G.SEP in lg[2]]
single = [lg for lg in sep_rows if lg[1] == 1]
multi = [lg for lg in sep_rows if lg[1] > 1]
print(f"logical rows in the oracle capture         : {len(G.logical_rows(orc))}")
print(f"  of which the text contains ']   py=['     : {len(sep_rows)}")
print(f"    of those, SINGLE physical line          : {len(single)}")
print(f"    of those, MULTI physical line (continuation inside the value): {len(multi)}")
print()
print("the multi-line ones (the SEP sits on the FIRST physical line; the value continues):")
for lg in multi:
  print(f"  L{lg[0]:>3} ({lg[1]} lines)  {lg[2].splitlines()[0][:70]}")
print()
print("  ==> A COUNTER THAT SEES THE SEP ONLY ON A ROW'S LAST PHYSICAL LINE SEES", len(multi), ";")
print("      A COUNTER THAT SEES IT ONLY ON A ROW'S FIRST PHYSICAL LINE SEES", len(single) + 0)
print("      (the SEP is on the FIRST physical line of every multi-line row, never the last).")

print()
print("=" * 78)
print("THE SHIPPED READER'S KEY COUNTS -- the docstring's '97' and '85'")
print("=" * 78)
print(f"  port   : rows() -> {len(set(G.rows_shipped(port))):4} distinct keys over {len(port.splitlines())} lines"
      f"   (docstring says 97 over 140)")
print(f"  oracle : rows() -> {len(set(G.rows_shipped(orc))):4} distinct keys over {len(orc.splitlines())} lines"
      f"   (docstring says 85 over 124)")
for label, text in (("port", port), ("oracle", orc)):
  c = G._census.measure(text, label)
  print(f"  {label:7} eq-census2.measure: accepted={c['accepted']} shipped_names={c['shipped_names']} "
        f"cont={c['cont']} lost_reader={c['lost_reader']} lost_cont={c['lost_cont']}")

print()
print("=" * 78)
print("THE REBASE-GATE BASELINE LANE 'cpython:render-gate-oracle' IN oracles/baseline.json")
print("=" * 78)
b = json.loads((REPO / "oracles/baseline.json").read_text())
lanes = b["lanes"]
print(f"  lanes: {len(lanes)}   names containing 'render': "
      f"{[k for k in lanes if 'render' in k]}")
for k in lanes:
  if "render" in k:
    v = lanes[k]
    if isinstance(v, dict):
      print(f"  {k}: {len(v)} entries; first 3: {list(v)[:3]}")
    else:
      print(f"  {k}: {type(v).__name__} {str(v)[:120]}")
