#!/usr/bin/env python3
"""analyse.py -- the NAMED lists this decision needs, derived from the fresh `codes.rows`.

One reading, one script, so the numbers in `decision.md` come from ONE run of ONE file and
cannot disagree with each other.
"""
import ast
import re
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ROWS = HERE / "codes.rows"

V = {"PASS", "FAIL", "REFUSED", "SKIP", "DEAD"}
rows = []
for line in ROWS.read_text().splitlines()[1:]:
    if not line.strip():
        continue
    rel, code, verdict, declared, note = line.split("\t", 4)
    rows.append((rel, code, verdict, declared, note))

print(f"ROWS {len(rows)}")

# ---- class sizes
c = Counter(r[2] for r in rows)
print("CLASSES", dict(c))

# ---- UNOWNED, named, with the argparse question answered per file
print("\n== UNOWNED ==")
unowned = [r for r in rows if r[2] == "UNOWNED"]
for rel, code, _, dec, note in unowned:
    src = (ROOT / rel).read_text(errors="replace")
    uses_argparse = bool(re.search(r"^\s*import\s+argparse|^\s*from\s+argparse\s+import", src, re.M))
    print(f"  {rel} code={code} declared={dec} argparse={uses_argparse}")

# ---- UNDECLARED: the sharp set (declares one code, omits another)
by_inst = defaultdict(dict)
for rel, code, verdict, dec, note in rows:
    if verdict in V:
        by_inst[rel][code] = dec
sharp = []
only_zero = []
for rel, d in sorted(by_inst.items()):
    und = [k for k, v in d.items() if v == "no"]
    dec = [k for k, v in d.items() if v == "yes"]
    if und and dec:
        sharp.append((rel, sorted(dec, key=int), sorted(und, key=int)))
    elif und and set(und) == {"0"}:
        only_zero.append(rel)
print(f"\n== SHARP (declares >=1 code, omits >=1 VERDICT-named code): {len(sharp)} instruments ==")
for rel, dec, und in sharp:
    print(f"  {rel}: declares {dec}, undeclared {und}")
print(f"\n== ONLY-0 UNDECLARED: {len(only_zero)} instruments")

# ---- UNDECLARED rows by verdict
print("\n== UNDECLARED ROWS BY VERDICT ==",
      dict(Counter(r[2] for r in rows if r[2] in V and r[3] == "no")))

# ---- MESSAGE-EXIT, named with its site count
print("\n== MESSAGE-EXIT ==")
for rel, code, verdict, dec, note in rows:
    if verdict == "MESSAGE-EXIT":
        sites = re.search(r"(\d+) site", note)
        print(f"  {rel}: {sites.group(1) if sites else '?'} site(s)")

# ---- the fixture / staging contamination of the population
print("\n== POPULATION CONTAMINATION ==")
fixture = sorted({r[0] for r in rows if "/.e2e-fixture/" in r[0] or r[0].startswith("checks/.e2e-fixture/")})
staging = sorted({r[0] for r in rows if "/.tmp" in r[0] or r[0].split("/")[-1].startswith(".tmp")})
print(f"  rows under checks/.e2e-fixture/ : {len(fixture)} instruments")
for f in fixture:
    print(f"    {f}")
print(f"  staging temps (.tmp*)             : {len(staging)} instruments")
for f in staging:
    print(f"    {f}")

# ---- the three UNOWNED codes of checks/e2e.py, at the line the census names
print("\n== checks/e2e.py exit roots ==")
src = (ROOT / "checks/e2e.py").read_text(errors="replace")
tree = ast.parse(src)
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "exit":
        arg = n.args[0] if n.args else None
        print(f"  line {n.lineno}: {ast.unparse(arg)[:90] if arg is not None else 'NO ARG'}")
