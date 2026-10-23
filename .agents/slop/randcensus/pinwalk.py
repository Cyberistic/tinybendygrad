#!/usr/bin/env python3
"""pinwalk.py -- WALK THE GATE'S OWN PINS against the two lanes, and name every one that moved.

    .venv/bin/python .agents/slop/randcensus/pinwalk.py

THE POPULATION IS THE GATE'S OWN `DIVERGES` TABLE, LOADED BY PATH -- not a hand list of the
pins that happened to fail. `gatekit`'s check returns on the FIRST moved pin, so a gate that
went red on `st_zero_g` says NOTHING about whether `st_six_g` also moved; this walk answers
that question for every pin at once.

It also prints the port-only rows' presence, the `NEG` class's rows and their values, and the
C-Python-side pin values, so the report can name rows rather than count them.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))

# THE GATE FILE'S NAME HAS A HYPHEN, so it is LOADED BY PATH and not imported by name.
_spec = importlib.util.spec_from_file_location("rand_census_gate", ROOT / "gates" / "rand_census-gate.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
DIVERGES, NEG, PORT_ONLY = _mod.DIVERGES, _mod.NEG, _mod.PORT_ONLY

SLOP = Path(__file__).resolve().parent
bd = (SLOP / "bd.out").read_text().splitlines()
py = (SLOP / "py.rows").read_text().splitlines()


def rows(lines):
  out = {}
  for l in lines:
    if not l.strip():
      continue
    k, _, v = l.partition("=")
    out[k] = (l, v)
  return out


BD, PY = rows(bd), rows(py)

print(f"== LANE SIZES  bd={len(bd)}  py={len(py)}")
print()
print("== DIVERGES PINS, EVERY ONE, BOTH SIDES")
moved = []
for row, (want_py, want_bd) in DIVERGES.items():
  for lane, want, table in (("py", want_py, PY), ("bd", want_bd, BD)):
    got, exact = table.get(row, ("<ABSENT>", ""))
    ok = (want in got)
    tag = "MATCH  " if ok else "MOVED  "
    if not ok:
      moved.append((row, lane, want, got))
    print(f"  {tag} {lane}'s {row}: pin={'present' if want in got else 'ABSENT'}")
    if not ok:
      print(f"        want={want!r}")
      print(f"        got ={got!r}")
print()
print(f"== DIVERGES MOVED: {len(moved)} of {2 * len(DIVERGES)} pin slots")
print()
print("== NEG CLASS ROWS AND THEIR VALUES (bd lane)")
for r in NEG:
  got = BD.get(r, ("<ABSENT>", ""))[1]
  print(f"  {r:<20} = {got}")
print()
print("== PORT-ONLY ROWS: presence in bd, absence in py")
for r in PORT_ONLY:
  in_bd = r in BD
  in_py = r in PY
  flag = "OK " if (in_bd and not in_py) else "!! "
  print(f"  {flag}{r:<20} bd={'yes' if in_bd else 'NO '}  py={'yes' if in_py else 'no'}")
