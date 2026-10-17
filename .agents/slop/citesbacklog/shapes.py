#!/usr/bin/env python3
"""Price candidate classifier fixes WITHOUT re-judging anything.

One extraction-only pass (`census()`, no `judge()`, no per-claim `read()`, no git per
claim) gives the shape fields lane C claims carry in memory (`gap`, `needle`).  Lane D
claims carry NO gap -- so the lane-D rules are priced from the citing LINE, read at the
row's own `file:at` anchor, which is an UPPER BOUND on the gap rule and is stated as one.
`verdicts.rows` -- the gate's OWN `--rows` output -- carries the verdict for every claim.

usage: shapes.py <verdicts.rows>
"""
import importlib.util
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cites", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

ENUM = re.compile(r"^[\s]*(?:[.,;·•]|->|→|/)[ ]*$")

rows = [l.rstrip("\n").split("\t") for l in Path(sys.argv[1]).read_text().splitlines()]
keys = Counter((f[0], f[3], f[4]) for f in rows)
print(f"verdicts.rows: {len(rows)} rows, {len(keys)} DISTINCT (lane,file:at,subject) keys, "
      f"{len(rows) - len(keys)} colliding rows (the join is lossy at that count)")
verdict = {}
for f in rows:
  verdict.setdefault((f[0], f[3], f[4]), f[2])
paths = cc.committed()
claims, _ = cc.census(paths)
joined = [(c, verdict[(c["lane"], f"{c['file']}:{c.get('at','')}", c.get("subject", ""))])
         for c in claims if (c["lane"], f"{c['file']}:{c.get('at','')}", c.get("subject", "")) in verdict]
print(f"JOINED {len(joined)}/{len(claims)} claims; verdicts.rows holds no lane E (27,666 SKIP mentions)")

print("\n--- LANE C CLASSIFIER WIDENINGS (N = FAIL retired, M = PASS silenced) ---")


def price(name, lanes, pred):
  n = m = r = 0
  for c, v in joined:
    if c["lane"] in lanes and pred(c):
      n += v == "FAIL"
      m += v == "PASS"
      r += v == "REFUSED"
  print(f"{name:<60} N={n:<5} M={m:<5} already-REFUSED={r}")


price("C: needle has brackets/braces but NO parentheses -- `code`'s blind spot", {"C"},
      lambda c: not ("(" in c["needle"] and ")" in c["needle"])
      and (("[" in c["needle"] and "]" in c["needle"]) or ("{" in c["needle"] and "}" in c["needle"])))
price("C: gap is an ENUMERATION separator -- the next list item is not a predicate", {"C"},
      lambda c: bool(ENUM.match(c.get("gap", "") or "")))
price("C: needle is an ALL-CAPS token", {"C"},
      lambda c: c["needle"].strip("*… ").isupper() and any(ch.isalpha() for ch in c["needle"]))
price("C: needle contains a SPACE (a phrase, not a literal)", {"C"},
      lambda c: " " in c["needle"].strip("*… "))
price("C: needle is a DOTTED name, no space, no slash (qualified symbol)", {"C"},
      lambda c: " " not in c["needle"].strip("*… ") and "." in c["needle"].strip("*… ")
      and "/" not in c["needle"])
price("C: needle contains ANY dot at all (the widest dotted rule)", {"C"},
      lambda c: "." in c["needle"])
price("C: citing LINE is a markdown table row", {"C"},
      lambda c: c.get("line_text", "").lstrip().startswith("|"))

PUNCT = re.compile(r"^[|`'\".,;·•…→>~—–-]*$")
print("\n--- LANE C: THE ADJACENCY RULE (`_is_connector`), PRICED AS ONE REGEX ---")
for name, pred in (
        ("gap is PUNCTUATION ONLY -- a table cell / list separator, not a connector",
         lambda c: bool(PUNCT.match(c.get("gap", "") or "")) and not (c.get("gap") or "").isspace()),
        ("gap contains a PIPE -- the needle is in the NEXT TABLE CELL",
         lambda c: "|" in (c.get("gap", "") or "")),
        ("gap contains a MIDDOT -- the needle is the NEXT LIST ITEM",
         lambda c: "·" in (c.get("gap", "") or "")),
        ("gap contains an ASCII DOT surrounded by spaces -- enumeration",
         lambda c: " . " in (c.get("gap", "") or ""))):
  price(name, {"C"}, pred)

print("\n--- LANE D, PRICED FROM THE CITING LINE (UPPER BOUND: gap ⊆ line) ---")
lines = {}
for c, v in joined:
  if c["lane"] == "D" and (c, v) not in lines:
    try:
      lines[(c["file"], c.get("at"))] = (ROOT / c["file"]).read_text(errors="replace").splitlines()[c["at"] - 1]
    except (OSError, IndexError):
      lines[(c["file"], c.get("at"))] = ""
price("D: the citing LINE carries OUTPUT (-> or rc=) -- a RUN's stdout", {"D"},
      lambda c: bool(cc.OUTPUT.search(lines.get((c["file"], c.get("at")), ""))))
price("D: the claiming line is a markdown table row", {"D"},
      lambda c: lines.get((c["file"], c.get("at")), "").lstrip().startswith("|"))

print("\n--- LANE D: the `wc -l` CONVENTION, FROM THE ROWS' OWN EVIDENCE ---")
NUM = re.compile(r"has (\d+) lines, claim says (\d+)")
wc = split = 0
for f in rows:
  if f[0] != "D" or f[2] != "FAIL":
    continue
  m = NUM.search(f[6])
  if not m:
    continue
  split, claim = int(m.group(1)), int(m.group(2))
  if split == claim + 1:
    wc += 1
print(f"D FAIL rows whose measured splitlines() is claim+1 (the wc -l shape): {wc}/66")

print("\n--- LANE DENOMINATORS, FROM THE JOIN ---")
for lane in "BCD":
  v = Counter(v for c, v in joined if c["lane"] == lane)
  f = [c for c, v in joined if c["lane"] == lane and v == "FAIL"]
  d = Counter(c["file"] for c in f)
  print(f"LANE {lane}: {dict(v)}  FAIL files={len(d)}  "
        + ", ".join(f"{k}={n}" for k, n in d.most_common(5)))