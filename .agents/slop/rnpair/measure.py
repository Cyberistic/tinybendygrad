#!/usr/bin/env python3
"""measure.py -- measure the rn-gate selftest's requirements against the candidates.

READ-ONLY. Imports `checks/rn-gate.py` BY PATH and uses ITS OWN readers
(`logical_rows`, `row_strict`, `rows_strict`, `judge`, `plant_value`, `plant_shape`),
so nothing here is a second copy of a reader.

The selftest lane is exercised by monkeypatching the gate's own `HERE` so that
`gate.selftest()` reads `rn-port.txt` / `rn-orc.txt` from THIS directory. That runs
the gate's selftest VERBATIM -- no re-implementation of its four lanes.
"""
import hashlib
import importlib.util
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, str(path))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


G = load("rn_gate", REPO / "checks" / "rn-gate.py")

CAND = REPO / "oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows"
FLIP = REPO / ".agents/slop/flipthird/base-render.err"
FLIP2 = REPO / ".agents/slop/flipthird/e2-base-tinybendygrad_uop_render.err"

SEP = G.SEP
ROW_OPEN = G.ROW_OPEN


def md5(t):
  return hashlib.md5(t.encode()).hexdigest()


def hdr(s):
  print("\n" + "=" * 78)
  print(s)
  print("=" * 78)


def shapes(text):
  """Which `py=` column spelling each PHYSICAL line carries, counted."""
  from collections import Counter
  c = Counter()
  for line in text.splitlines():
    if "]   py=[" in line:
      c["three-space BRACKETED  ]   py=["] += 1
    elif "]   py=" in line:
      c["three-space bare      ]   py="] += 1
    elif "]     py=" in line:
      c["five-space bare       ]     py="] += 1
    elif "] py=" in line:
      c["one-space bare        ] py="] += 1
    elif "py=" in line:
      c["py= with other spacing/position"] += 1
    else:
      c["NO py= column at all"] += 1
  return c


def describe(name, text):
  hdr(f"CANDIDATE: {name}   ({len(text.splitlines())} physical lines, md5 {md5(text)[:8]})")
  print(f"  logical rows (gate's logical_rows): {len(G.logical_rows(text))}")
  rows, refusals = G.rows_strict(text)
  print(f"  rows_strict -> {len(rows)} names, {len(refusals)} refusals")
  if refusals:
    print(f"  refusals[:6]: {refusals[:6]}")
  print("  separator shapes over physical lines:")
  for k, v in sorted(shapes(text).items()):
    print(f"    {v:5}  {k}")
  # which names carry the SEP, and which do not
  withsep, without = [], []
  for lg in G.logical_rows(text):
    (withsep if SEP in lg[2] else without).append(lg[2].splitlines()[0][:58])
  print(f"  logical rows carrying the gate's SEP {SEP!r}: {len(withsep)}")
  print(f"  logical rows NOT carrying it: {len(without)}")
  return rows, refusals


def judge_pair(pname, ptext, oname, otext):
  hdr(f"PAIR: port={pname}  oracle={oname}")
  r = G.judge(ptext, otext)
  print(f"  port logical rows : {len(r['port'])}")
  print(f"  oracle logical rows: {len(r['oracle'])}")
  print(f"  gated={len(r['gated'])}  agree={len(r['agree'])}  disagree={len(r['disagree'])}")
  print(f"  disagree names: {[d[0] for d in r['disagree']]}")
  print(f"  stray (oracle-only): {sorted(set(r['oracle']) - set(r['port']))}")
  print(f"  ghost (port-only)  : {sorted(set(r['port']) - set(r['oracle']))}")
  print(f"  byte-identical: {r['identical_bytes']}")
  for m in r["reshape"]:
    print(f"  lane {m['lane']:<7} physical={m['physical']} logical={m['logical']} cont={m['cont']} "
          f"eq={len(m['eq'])} lost={m['lost']} refusals={len(m['refusals'])}")
  print("  bad:")
  for b in r["bad"]:
    print(f"    - {b[:400]}")
  return r


def selftest_verbatim(port_text, orc_text, label):
  """Run the gate's OWN selftest() against this pair, by moving the gate's HERE."""
  (HERE / "rn-port.txt").write_text(port_text)
  (HERE / "rn-orc.txt").write_text(orc_text)
  old = G.HERE
  G.HERE = HERE
  try:
    hdr(f"GATE'S OWN selftest() OVER: {label}")
    rc = G.selftest()
    print(f"  selftest() returned {rc}")
    return rc
  finally:
    G.HERE = old
    (HERE / "rn-port.txt").unlink(missing_ok=True)
    (HERE / "rn-orc.txt").unlink(missing_ok=True)


orc_text = CAND.read_text()
flip_text = FLIP.read_text()
flip2_text = FLIP2.read_text()
# the flipthird .err is stderr MIXED with bend's uop dump; the row block starts at the
# first `pyrender ` line.  Both slices are measured so the report can name which is which.
flip_rows_only = flip_text[flip_text.index("pyrender const"):]

print("GATE CONSTANTS")
print(f"  SEP       = {SEP!r}")
print(f"  ROW_OPEN  = {ROW_OPEN!r}")
print(f"  PORT      = {G.PORT!r}")
print(f"  ORACLE    = {G.ORACLE!r}   exists={ (REPO / G.ORACLE[0]).is_file() }")

orc_rows, orc_ref = describe("oracles/...render-gate-oracle.rows", orc_text)
flip_rows, flip_ref = describe(".agents/slop/flipthird/base-render.err (WHOLE stderr mix)", flip_text)
f2_rows, f2_ref = describe(".agents/slop/flipthird/base-render.err (ROW BLOCK ONLY)", flip_rows_only)

print("\nROW-SET DIAGNOSTIC (name sets, not counts)")
print(f"  oracle names: {len(orc_rows)}")
print(f"  flip  names: {len(flip_rows)}  (whole file)")
print(f"  flip2 names: {len(f2_rows)}  (row block only)")
print(f"  in flip(whole) but NOT in oracle: {sorted(set(flip_rows) - set(orc_rows))}")
print(f"  in flip(rowblock) but NOT in oracle: {sorted(set(f2_rows) - set(orc_rows))}")
print(f"  in oracle but NOT in flip(whole): {sorted(set(orc_rows) - set(flip_rows))}")

judge_pair("flipthird WHOLE .err", flip_text, "oracles candidate", orc_text)
judge_pair("flipthird ROW BLOCK", flip_rows_only, "oracles candidate", orc_text)
judge_pair("flipthird e2 .err WHOLE", flip2_text, "oracles candidate", orc_text)
