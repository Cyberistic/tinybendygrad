#!/usr/bin/env python3
# dd-cmp.py -- compare the port's gate text against CPython's, on whole
# `name=value` lines.
#
# RULE 73 IS WHY THIS EXISTS: a gate that compares row NAMES cannot see a
# mutation that changes only the VALUE.  So the unit of comparison is the whole
# left-hand side of a line, i.e. `lg3sig=...` is one unit and `lg3` is a
# different unit -- two ports that print the same 121 NAMES and 55 different
# VALUES score 121/121 on a name comparison.
#
# usage: dd-cmp.py PORT.txt ORACLE.txt [--only] [--names N1,N2]
#   --only     print only the disagreeing rows, no summary
#   --kinds    classify each disagreement (refuse-vs-answer / node-count / ...)
import sys

def load(path):
    d = {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d

def kinds(port, ora, key):
    pv, ov = port.get(key), ora.get(key)
    if pv is None or ov is None:
        return "MISSING(port=%s ora=%s)" % (pv is not None, ov is not None)
    if pv == ov:
        return "AGREE"
    if pv == "none" and ov.startswith("refused:"):
        return "REFUSE-vs-ANSWER"
    if ov.startswith("refused:") and pv != ov:
        return "ANSWER-vs-REFUSE"
    if key.endswith("n"):
        return "COUNT"
    if key.endswith("sig"):
        pn = pv.split(",") if pv else []
        on = ov.split(",") if ov else []
        pn = [x for x in pn if x]
        on = [x for x in on if x]
        from collections import Counter
        cp, co = Counter(pn), Counter(on)
        onlyp = sorted((cp - co).elements())
        onlyo = sorted((co - cp).elements())
        if cp == co and pn != on:
            return "SIG-MULTISET-ONLY-ORDER"
        if not onlyp and not onlyo:
            return "SIG-ORDER"
        if onlyp and onlyo:
            return "SIG-BOTH(%d+/%d-)" % (len(onlyp), len(onlyo))
        return "SIG-EXTRA-PORT(%d)" % len(onlyp)
    if key.endswith("k"):
        return "CONSTS"
    return "VALUE"

def main():
    a = sys.argv[1:]
    only, kind = "--only" in a, "--kinds" in a
    a = [x for x in a if not x.startswith("--")]
    port, ora = load(a[0]), load(a[1])
    # A row ABSENT FROM BOTH lanes is not a row; comparing None to None would
    # report agreement for a fixture column the oracle never prints.
    keys = [k for k in port if k in ora]
    absent = [k for k in port if k not in ora]
    dis = [(k, port.get(k), ora.get(k)) for k in keys if port.get(k) != ora.get(k)]
    if only:
        for k, pv, ov in dis:
            print("%s\n  port=%s\n  ora =%s" % (k, pv, ov))
        return
    print("gate rows: %d   oracle rows: %d   agreeing: %d   disagreeing: %d"
          % (len(keys), len(ora), len(keys) - len(dis), len(dis)))
    print("gate coverage of oracle: %d/%d = %.1f%%"
          % (len(keys), len(ora), 100.0 * len(keys) / len(ora)))
    if absent:
        print("gate rows the oracle does not print: %d %s" % (len(absent), " ".join(absent[:8])))
    if kind:
        from collections import Counter
        c = Counter(kinds(port, ora, k) for k in keys if port.get(k) != ora.get(k))
        for k, v in c.most_common():
            print("  %-28s %d" % (k, v))
    else:
        for k, pv, ov in dis:
            print("  %-10s port=%s ora=%s" % (k, pv, ov[:120]))

main()