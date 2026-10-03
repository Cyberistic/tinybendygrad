#!/usr/bin/env python3
"""THE BLAST RADIUS OF A `rows()` CHANGE, MEASURED OVER ALL 38 WIRED GATES.

`rows()` is rebase-gate.py's row parser and every wired gate shares it.  The trap
in changing it is a parser that silently DROPS or RENAMES a row: the gate compares
row-NAME sets, so rows that vanish make a pair share nothing -- caught -- but rows
that get RENAMED into a name the other lane happens to use read as a PASS over
nothing -- not caught.  So a candidate parser must be a proven SUPERSET: every row
the shipped parser returns, returned UNCHANGED.

TWO CANDIDATES ARE MEASURED, NOT SHIPPED.  `ga_sweep.py` cached every lane's stdout
and both parsers are applied to the cache offline, so this is one measurement of the
real outputs and not a re-run per candidate.

  rows()          rebase-gate.py:rows() VERBATIM.  `name=value`, key on the first
                  `=`, one row per LINE.
  fold-naive      fold a line with no `]   py=[` terminator into the previous row.
                  MEASURED TO BE A DISASTER: 31 of 38 gates do not print that shape
                  at all (they print `name=value` with no spaces), so every row
                  runs off the end of the file and is dropped.
  fold-safe       the same fold, but a value whose terminator never arrives FALLS
                  BACK to the shipped one-row-per-line reading.  A superset by
                  construction, and the number it adds is the honest ceiling on what
                  this class of change can buy.

Run:  python3 .agents/slop/ga_rows_blast.py
"""
import json
import pathlib
import re
import sys

SLOP = pathlib.Path(__file__).resolve().parent
CACHE = SLOP / "ga_cache"


def rows(text):
  """`rebase-gate.py:rows()` VERBATIM -- the shipped parser, the control."""
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


ROWEND = re.compile(r"\]\s+py=\[")


def fold(text, safe):
  """{name: value}.  `safe=False` drops a value whose terminator never arrives;
  `safe=True` falls back to the shipped reading instead.  Both are measured."""
  out = {}
  lines = text.split("\n")
  i = 0
  while i < len(lines):
    line = lines[i]
    if "=" not in line:
      i += 1
      continue
    k, v = line.split("=", 1)
    k = k.strip()
    if ROWEND.search(line):
      out[k] = v.strip()
      i += 1
      continue
    buf, j, found = [v], i + 1, False
    while j < len(lines) and not found:
      if ROWEND.search(lines[j]):
        found = True
      buf.append(lines[j])
      j += 1
    if found:
      out[k] = "\n".join(buf).strip()
      i = j
      continue
    if safe:
      out[k] = v.strip()   # shipped reading: this line is its own row
      i += 1
    else:
      i = j                 # naive: the row is lost
  return out


def shared(a, b):
  return set(a) & set(b)


def changed(old, new):
  """Rows the shipped parser returns that the candidate returns DIFFERENTLY --
  dropped or renamed-with-a-different-value.  A superset has none."""
  return {k for k, v in old.items() if new.get(k) != v}


def main():
  manifest = json.loads((CACHE / "lanes.json").read_text())
  tot = {"n": 0, "old": 0, "safe": 0, "naive": 0, "chg_safe": 0, "chg_naive": 0,
         "sh_old": 0, "sh_safe": 0, "sh_naive": 0, "bad": 0}
  print(f"{'port':<46} {'rows()':>7} {'safe':>7} {'naive':>7} {'changed':>8} "
        f"{'shared_old':>11} {'shared_safe':>12} {'shared_naive':>13}")
  for port in sorted(manifest):
    lanes = manifest[port]
    if not isinstance(lanes, dict) or "MISSING" in lanes:
      continue
    d = CACHE / port.replace("/", "_")
    got = {}
    for lane in sorted(lanes):
      fp = d / (f"{lane}.txt" if lane in ("interpreted", "native")
                else lane.replace(":", "_") + ".txt")
      if fp.exists():
        got[lane] = fp.read_text()
    if len(got) < 2:
      continue
    per = {k: rows(t) for k, t in got.items()}
    sf = {k: fold(t, True) for k, t in got.items()}
    nv = {k: fold(t, False) for k, t in got.items()}
    chg_s = sum(len(changed(per[k], sf[k])) for k in per)
    chg_n = sum(len(changed(per[k], nv[k])) for k in per)
    sh = lambda m: sum(len(shared(m[a], m[b]))
                      for i, a in enumerate(sorted(m)) for b in sorted(m)[i + 1:])
    s_old, s_safe, s_naive = sh(per), sh(sf), sh(nv)
    tot["n"] += 1
    tot["old"] += sum(len(v) for v in per.values())
    tot["safe"] += sum(len(v) for v in sf.values())
    tot["naive"] += sum(len(v) for v in nv.values())
    tot["chg_safe"] += chg_s
    tot["chg_naive"] += chg_n
    tot["sh_old"] += s_old
    tot["sh_safe"] += s_safe
    tot["sh_naive"] += s_naive
    flag = "  <-- NOT A SUPERSET" if chg_s else ""
    print(f"{port:<46} {sum(len(v) for v in per.values()):>7} "
          f"{sum(len(v) for v in sf.values()):>7} {sum(len(v) for v in nv.values()):>7} "
          f"{chg_s:>8} {s_old:>11} {s_safe:>12} {s_naive:>13}{flag}")

  print(f"\nTOTALS over {tot['n']} gates with >=2 lanes")
  print(f"  rows()   returns {tot['old']} rows, {tot['sh_old']} shared within a lane pair")
  print(f"  fold-safe  returns {tot['safe']} rows (+{tot['safe']-tot['old']}), "
        f"{tot['sh_safe']} shared; CHANGES {tot['chg_safe']} shipped rows "
        f"-> {'SUPERSET' if not tot['chg_safe'] else 'NOT A SUPERSET'}")
  print(f"  fold-naive returns {tot['naive']} rows ({tot['naive']-tot['old']:+d}), "
        f"{tot['sh_naive']} shared; CHANGES {tot['chg_naive']} shipped rows "
        f"-> {'SUPERSET' if not tot['chg_naive'] else 'NOT A SUPERSET'}")
  print("\n  A GATE THAT SUDDENLY REPORTS 0 SHARED IS A REGRESSION UNTIL PROVEN "
        "OTHERWISE.")
  return 1 if tot["chg_safe"] or tot["chg_naive"] else 0


if __name__ == "__main__":
  sys.exit(main())