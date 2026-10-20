#!/usr/bin/env python3
"""measure2.py -- THE DECISIVE EXPERIMENT for the rn-gate `--selftest` lane.

READ-ONLY against the tree. It uses the gate's OWN `selftest()` -- imported by path,
with the gate's own `HERE` moved to this directory so `selftest()` reads the two
captures from here.  Nothing about the selftest's four lanes is re-implemented.

The pair under test:
  ORACLE  = oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows   (the whole file)
  PORT    = .agents/slop/flipthird/base-render.err lines 22..161
            (the 11 `rnd_*` rows + the 140-line row block; the surrounding 21 lines of
             bend's uop dump and the 2 lines of watchdog/bend stderr are excluded)

and the 140-line slice's md5 is checked against the md5 the gate's own docstring records.
"""
import hashlib
import importlib.util
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("rn_gate", REPO / "checks" / "rn-gate.py")
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)

CAND = REPO / "oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows"
FLIP = REPO / ".agents/slop/flipthird/base-render.err"

DOC_PORT_MD5 = "302944bb48a32379"     # checks/rn-gate.py docstring, "port stdout md5"
DOC_ORC_MD5 = "642f9770c558df0f1be03a8f67ac997e"   # docstring, "oracle stdout md5"


def md5(t):
  return hashlib.md5(t.encode()).hexdigest()


def slice_port():
  """lines 22..161 of the flipthird stderr capture = the 140 stdout row lines."""
  lines = FLIP.read_text().splitlines(keepends=True)
  return "".join(lines[21:161])


port = slice_port()
orc = CAND.read_text()

print("=" * 78)
print("THE PAIR")
print("=" * 78)
print(f"PORT   {FLIP.relative_to(REPO)} lines 22..161")
print(f"       {len(port.splitlines())} lines, {len(port.encode())} bytes, md5 {md5(port)}")
print(f"       docstring's recorded port stdout md5 = {DOC_PORT_MD5}  ->  MATCH={md5(port).startswith(DOC_PORT_MD5)}")
print(f"ORACLE {CAND.relative_to(REPO)}")
print(f"       {len(orc.splitlines())} lines, {len(orc.encode())} bytes, md5 {md5(orc)}")
print(f"       docstring's recorded oracle stdout md5 = {DOC_ORC_MD5}  ->  MATCH={md5(orc) == DOC_ORC_MD5}")

print()
print("=" * 78)
print("WHAT THE GATE'S READERS MAKE OF EACH SIDE")
print("=" * 78)
for label, text in (("PORT", port), ("ORACLE", orc)):
  rows, refusals = G.rows_strict(text)
  print(f"{label:7} logical rows={len(G.logical_rows(text)):4}  names={len(rows):4}  refusals={len(refusals)}  "
        f"md5={md5(text)[:8]}")
  if refusals:
    print(f"        refusals: {refusals[:8]}")
  print(f"        names with '=': {sorted(n for n in rows if '=' in n)}")

print()
print("=" * 78)
print("THE GATE'S OWN judge() OVER THE PAIR")
print("=" * 78)
r = G.judge(port, orc)
print(f"gated={len(r['gated'])}  agree={len(r['agree'])}  disagree={len(r['disagree'])}")
for d in r["disagree"]:
  print(f"  DISAGREE {d[0]!r}")
  print(f"     port {d[1]!r}")
  print(f"     orc  {d[2]!r}")
print(f"stray (oracle-only names): {sorted(set(r['oracle']) - set(r['port']))}")
print(f"ghost (port-only names)  : {sorted(set(r['port']) - set(r['oracle']))}")
print(f"byte-identical: {r['identical_bytes']}")
for m in r["reshape"]:
  print(f"  lane {m['lane']:<7} physical={m['physical']} logical={m['logical']} cont={m['cont']} "
        f"eq={len(m['eq'])} lost={m['lost']} lost_cont={m['lost_cont']} lost_reshape={m['lost_reshape']} "
        f"lost_dupe={m['lost_dupe']} refusals={len(m['refusals'])}")
print("bad:")
for b in r["bad"]:
  print(f"  - {b[:300]}")

print()
print("=" * 78)
print("THE GATE'S OWN selftest() -- VERBATIM, with HERE moved to this directory")
print("=" * 78)
(HERE / "rn-port.txt").write_text(port)
(HERE / "rn-orc.txt").write_text(orc)
old = G.HERE
G.HERE = HERE
try:
  rc = G.selftest()
  print(f"selftest() returned {rc}   ({'PASS' if rc == 0 else 'FAIL'})")
finally:
  G.HERE = old
  (HERE / "rn-port.txt").unlink(missing_ok=True)
  (HERE / "rn-orc.txt").unlink(missing_ok=True)

print()
print("=" * 78)
print("WHY 58 of the ORACLE's 80 ROWS CARRY NO ']   py=[' -- the four spellings")
print("=" * 78)
# the oracle's own printer, checks/render-gate-oracle.py emit_gate(), by name class
src = (REPO / "checks" / "render-gate-oracle.py").read_text()
for pat in (r"^_PY_ROW = .*$", r"^_IO1 = .*$", r"^_IO5 = .*$", r"^_SPLIT = .*$"):
  m = re.search(pat, src, re.M)
  print("  " + (m.group(0) if m else f"(no match {pat})"))
print()
K_PY = "_PY_ROW (pyrender */pyr_*)  -> ']   py=['"
K_SPLIT = "_SPLIT (5 arg_repr)   -> NO py= column"
K_IO1 = "_IO1 (3 sint_show)        -> '] py='"
K_IO5 = "_IO5 (3 f32_repr)        -> ']     py='"
K_DEF = "default                   -> ']   py='"
classes = {K_PY: 0, K_SPLIT: 0, K_IO1: 0, K_IO5: 0, K_DEF: 0}
for lg in G.logical_rows(orc):
  first = lg[2].splitlines()[0]
  if first.startswith(("pyrender ", "pyr_")):
    classes[K_PY] += 1
  elif first.split("=")[0].strip() in (
      "arg_repr AKern", "arg_repr AProgr", "arg_repr AParam1", "arg_repr AParam2", "arg_repr AParam3"):
    classes[K_SPLIT] += 1
  elif first.startswith(("sint_show 2**31-1", "sint_show -3", "sint_show -2**31")):
    classes[K_IO1] += 1
  elif first.startswith("f32_repr"):
    classes[K_IO5] += 1
  else:
    classes[K_DEF] += 1
for k, v in classes.items():
  print(f"  {v:3}  {k}")
nsep = classes[K_PY]
print(f"  ---  rows whose py= column IS the gate's SEP ']   py=[' : {nsep}")
print(f"  ---  rows whose py= column is NOT the SEP                : {80 - nsep}")
