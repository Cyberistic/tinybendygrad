# dd-gap.py -- WHAT IS MISSING from a cone, as a MULTISET difference.
"""
dd-cmp.py answers "do these rows disagree". This answers "which nodes", because the
CDIV/CMOD disagreements (`lgq*/lgr*/lgs*/lgt*`) are 92-2500 nodes wide and a diff of two
4000-character strings does not name a single one of them.

`CONE ORDER` is a property of the row (`sig` is documented as DFS pre-order), so
a difference here is a shape difference and not a spelling difference. The diff is on
MULTISETS (Counter), because `sig` dedups shared nodes and so does the oracle's `cone`
-- a list difference would report every shared node twice.

  dd-gap.py PORT.txt ORACLE.txt ROW [ROW...]      the op multiset difference
  dd-gap.py PORT.txt ORACLE.txt --k ROW [ROW...]   the CONST-value multiset difference
  dd-gap.py PORT.txt ORACLE.txt --full ROW         the FULL cone as a node list, both
"""
import sys
from collections import Counter


def load(path):
    d = {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


def items(v):
    return [x for x in v.split(",") if x]


def main():
    a = sys.argv[1:]
    full = "--full" in a
    mode = "--k" if "--k" in a else "--sig"
    a = [x for x in a if not x.startswith("--")]
    port, ora = load(a[0]), load(a[1])
    for row in a[2:]:
        key = row + ("k" if mode == "--k" else "sig")
        pv, ov = items(port.get(key, "")), items(ora.get(key, ""))
        if full:
            print(f"=== {key}: port {len(pv)}  oracle {len(ov)}")
            for i, x in enumerate(pv):
                print(f"  P{i:<4} {x}")
            print("  ---")
            for i, x in enumerate(ov):
                print(f"  O{i:<4} {x}")
            continue
        cp, co = Counter(pv), Counter(ov)
        onlyp = sorted((cp - co).elements())
        onlyo = sorted((co - cp).elements())
        print(f"=== {key}: port {len(pv)} nodes/{len(cp)} distinct, "
              f"oracle {len(ov)}/{len(co)}")
        print(f"  ONLY-ORACLE ({len(onlyo)}): {Counter(onlyo).most_common()}")
        print(f"  ONLY-PORT   ({len(onlyp)}): {Counter(onlyp).most_common()}")


main()