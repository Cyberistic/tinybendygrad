"""FLIPTHIRD: who BUILDS a FLIP's arg, today (line numbers re-measured).

Populations by DISCOVERY (doctrine 1) -- os.walk over the port, excluding the
untracked byte-identical nested copy at tinybendygrad/tinybendygrad/.

A "construction" is a line that calls UOp.new/UNode.new with an OpsFLIP on the
same line, or forms `O.ATuple` in a def whose name or body is FLIP-shaped.
This is deliberately LOOSE: it is a superset, so a site it misses cannot be
excused by the census -- and a site it reports is a candidate to READ.
"""
import os, re

ROOT, NESTED = "tinybendygrad", os.path.join("tinybendygrad", "tinybendygrad")
FLIP = re.compile(r"(OpsFLIP|Ops\.FLIP|t_mop_flip|pr_flip|mxw_flip|mx_flip|G\.flip)")

rows = []
for d, dirs, fs in os.walk(ROOT):
    if os.path.abspath(d).startswith(os.path.abspath(NESTED)):
        dirs[:] = []
        continue
    for f in sorted(fs):
        if not f.endswith(".bend"):
            continue
        p = os.path.join(d, f)
        src = open(p, encoding="utf-8", errors="replace").read().split("\n")
        for i, ln in enumerate(src):
            if not FLIP.search(ln):
                continue
            kind = ("CTOR" if re.search(r"\.(new)\(|UOp\.new|UNode\.new|O\.ATuple|ATuple\{", ln)
                    else "reader" if re.search(r"ATuple|marg|order_arg", ln)
                    else "other")
            rows.append((p, i + 1, kind, ln.strip()[:110]))

print("# FLIPTHIRD: FLIP sites, discovered by walk (nested duplicate excluded)")
print(f"# {len(rows)} FLIP-mentioning lines\n")
print("# file\tline\tkind\ttext")
for p, n, k, t in rows:
    print(f"{p}\t{n}\t{k}\t{t}")