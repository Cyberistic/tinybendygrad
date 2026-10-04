#!/usr/bin/env python3
"""I64DIV classify: WHICH FAMILY disagrees, and is int64.min an operand?

Reads got/expected, and answers the brief's two questions with counts:
  1. which def is wrong -- i64_div, i64_mod, cdiv_i64, cmod_i64, gcd, i64_dec?
  2. is every disagreement a row where int64.min is an operand?
"""
import sys, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
GOT = sys.argv[1] if len(sys.argv) > 1 else "before.txt"

W = 1 << 64
S = 1 << 63
def u(v): return v & (W - 1)
MIN = u(-S)

got = {}
for ln in open(os.path.join(HERE, GOT)):
    k, _, v = ln.strip().partition("=")
    if k: got[k] = v
exp = {}
for ln in open(os.path.join(HERE, "expected.txt")):
    k, _, v = ln.strip().partition("=")
    if k: exp[k] = v
wrap = {l.strip() for l in open(os.path.join(HERE, "wrap.txt")) if l.strip()}
zero = {l.strip() for l in open(os.path.join(HERE, "zero.txt")) if l.strip()}

# every row NAME ends in the two fixture operands (or is a bare i64_dec row),
# so the operands are recoverable from the row name -- no side table needed.
FAMILY = {"d": "i64_div", "m": "i64_mod", "c": "cdiv_i64",
          "k": "cmod_i64", "g": "gcd", "t": "i64_dec"}

# operands come from fixtures.tsv, which the GENERATOR wrote. Re-parsing the row
# name was the first version's approach and it is wrong: `c_n0` and
# `p0_-1_-9223372036854775808` parse as nothing, so 95 rows that DO have int64.min
# as an operand were counted as not having it.
FIX = {}
for ln in open(os.path.join(HERE, "fixtures.tsv")):
    nm, a, b = ln.rstrip("\n").split("\t")
    FIX[nm if nm.startswith("@") else nm] = (int(a), None if b == "-" else int(b))

def operands(key):
    """key is e.g. `c_g_-7_3` -> the fixture is `g_-7_3`."""
    body = key.split("_", 1)[1]
    return FIX.get(body)

by_fam = collections.Counter()
tot_fam = collections.Counter()
bad = collections.defaultdict(list)
for k in exp:
    fam = k.split("_", 1)[0]
    tot_fam[fam] += 1
    if k not in got:
        continue
    if got[k] != exp[k]:
        by_fam[fam] += 1
        bad[fam].append(k)

print(f"{GOT}: rows_expected={len(exp)} rows_present={len(got)} "
      f"missing={len(set(exp)-set(got))}")
print()
print(f"{'family':9} {'def':10} {'expected':>9} {'present':>9} {'missing':>8} {'disagree':>9}")
for fam in ("d", "m", "c", "k", "g", "t"):
    p = sum(1 for k in exp if k.startswith(fam + "_") and k in got)
    mi = sum(1 for k in exp if k.startswith(fam + "_") and k not in got)
    print(f"{fam+'_':9} {FAMILY[fam]:10} {tot_fam[fam]:>9} {p:>9} {mi:>8} {by_fam[fam]:>9}")

print()
print("=== DO ALL DISAGREEMENTS HAVE int64.min AS AN OPERAND? ===")
for fam in ("d", "m", "c", "k", "g", "t"):
    if not bad[fam]:
        continue
    withmin = [k for k in bad[fam] if (lambda o: o and (u(o[0]) == MIN or u(o[1]) == MIN))(operands(k))]
    unk = [k for k in bad[fam] if operands(k) is None]
    wo = len(bad[fam]) - len(withmin) - len(unk)
    print(f"  {FAMILY[fam]:10} disagree={len(bad[fam]):4}  with_int64.min={len(withmin):4}"
          f"  without={wo:4}  operands_unknown={len(unk)}")

print()
print("=== ROWS WHERE THE EXACT UPSTREAM ANSWER IS OUT OF RANGE (documented wrap) ===")
for k in sorted(wrap)[:30]:
    print(f"  {k:46} port={got.get(k,'MISSING'):>24} exact_upstream={exp[k]}")
print(f"  total wrap rows={len(wrap)}  of which currently disagreeing="
      f"{len([k for k in wrap if k in got and got[k]!=exp[k]])}")

print()
print("=== i64_dec LANE (`t_`): port vs str() ===")
for k in sorted(k for k in exp if k.startswith("t_")):
    mark = "  " if got.get(k) == exp[k] else "!!"
    print(f" {mark} {k:32} port={got.get(k,'MISSING'):>24} str={exp[k]}")
