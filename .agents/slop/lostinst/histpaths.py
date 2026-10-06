#!/usr/bin/env python
"""For each of the 16 absent instruments, list every path in ALL git history
whose basename matches, to detect copies/mirrors (DUPLICATE evidence)."""
import os, json, sys
hist = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/allhistpaths.txt'
paths = [l.strip() for l in open(hist) if l.strip()]
by_base = {}
for p in paths:
    by_base.setdefault(os.path.basename(p), set()).add(p)

recs = json.load(open('.agents/slop/lostinst/census.json'))
for r in recs:
    b = os.path.basename(r['path'])
    hits = sorted(by_base.get(b, []))
    print(f"== {r['path']}  [{r['state']}] basename={b}")
    if not hits:
        print("   no path with this basename anywhere in history")
    for h in hits:
        print("   ", h)
