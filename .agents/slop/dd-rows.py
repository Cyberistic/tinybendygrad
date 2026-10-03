#!/usr/bin/env python3
# dd-rows.py -- print the port's and the oracle's rows side by side, and for a
# `*sig` row the index of the FIRST differing element, so a family is attributed
# to a node rather than to a whole string.
#
#   dd-rows.py ROW [ROW...]        # rows
#   dd-rows.py --sig ROW           # first-divergence for a sig row
import sys
sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location("ddoracle", ".agents/slop/dd-oracle.py")
DDO = importlib.util.module_from_spec(spec)
sys.modules["ddoracle"] = DDO
spec.loader.exec_module(DDO)


def rows_of(path):
    d = {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


P = rows_of(sys.argv[1])
O = rows_of(sys.argv[2])
first_sig = False
if sys.argv[1] == "--sig":
    first_sig = True
    want = sys.argv[2:]
else:
    want = [a for a in sys.argv[1:] if not a.startswith("-")]

for k in want:
    print("--- %s" % k)
    print("  port = %s" % P.get(k))
    print("  ora  = %s" % O.get(k))
    if k.endswith("sig"):
        pn = P.get(k, "").split(",")
        on = O.get(k, "").split(",")
        pn = [x for x in pn if x]
        on = [x for x in on if x]
        if pn == on:
            print("  sig EQUAL (%d entries)" % len(pn))
            continue
        i = 0
        while i < min(len(pn), len(on)) and pn[i] == on[i]:
            i += 1
        print("  len port=%d ora=%d   first diff at index %d" % (len(pn), len(on), i))
        lo = max(0, i - 4)
        print("    port[%d:] %s" % (lo, ",".join(pn[lo:lo + 22])))
        print("    ora [%d:] %s" % (lo, ",".join(on[lo:lo + 22])))
