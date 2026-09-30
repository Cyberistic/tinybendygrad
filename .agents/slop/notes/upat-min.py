#!/usr/bin/env python3
"""Minimize a failing upatfuzz case: drop nodes, then blank fields, keeping the
mismatch alive. Both sides re-evaluated; no expectation is written by hand."""
import subprocess, sys, os
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/tools")
import upatfuzz as F

BIN = sys.argv[1]
CASE = sys.argv[2]
TMP = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/min.txt"


def wellformed(case):
    """The oracle must be ABLE to answer; a shape it refuses is not a diff."""
    try:
        F.oracle(case)
        return True
    except Exception:
        return False


def fails(case):
    if not wellformed(case):
        return False
    with open(TMP, "w") as f:
        f.write(case + "\n")
    try:
        r = subprocess.run([BIN, TMP], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return False
    return r.stdout.strip() != F.oracle(case)


assert fails(CASE), "the given case does not fail"
nodes = CASE.split("|")

# 1. drop trailing nodes (the root must stay, so keep >= 1)
changed = True
while changed:
    changed = False
    for i in range(1, len(nodes) - 1):
        cand = nodes[:i] + nodes[i + 1:]
        if fails("|".join(cand)):
            nodes = cand
            changed = True
            break

# 2. blank one field of one node at a time
changed = True
while changed:
    changed = False
    for i, n in enumerate(nodes):
        f = n.split(";")
        for j in range(len(f)):
            if f[j] == "-":
                continue
            g = f[:]
            g[j] = "-"
            cand = nodes[:]
            cand[i] = ";".join(g)
            if fails("|".join(cand)):
                nodes = cand
                changed = True
                break
        if changed:
            break

# 3. shrink child index lists
changed = True
while changed:
    changed = False
    for i, n in enumerate(nodes):
        f = n.split(";")
        if len(f) != 8:
            continue
        s = f[5]
        if s.startswith(("t", "l", "r")) and "," in s[1:]:
            kids = s[1:].split(",")
            for k in range(len(kids)):
                g = f[:]
                g[5] = s[0] + ",".join(kids[:k] + kids[k + 1:])
                cand = nodes[:]
                cand[i] = ";".join(g)
                if fails("|".join(cand)):
                    nodes = cand
                    changed = True
                    break
        if changed:
            break

case = "|".join(nodes)
print("MINIMAL:", case)
print("WANT:", F.oracle(case))
r = subprocess.run([BIN, TMP], capture_output=True, text=True, timeout=60)
print("GOT: ", r.stdout.strip())
