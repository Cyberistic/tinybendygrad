#!/usr/bin/env python3
"""prof_top.py -- THE HOT FUNCTIONS IN A BUN CPU PROFILE, BY SELF TIME.

THE TREE's OWN PROFILER IS `bun --cpu-prof` (PER `cstyle.bend`'s COMMENT AT :938: "MEASURED with
`bun --cpu-prof` on a 405-uop kernel: `render_dtype` was 58% of the whole render"). **=> AND THE
PROFILE IS A `.cpuprofile` (CHROME'S FORMAT), SO IT IS READ HERE.**

    .venv/bin/python prof_top.py <profile.cpuprofile> [n]
"""
import json
import pathlib
import sys
from collections import defaultdict


def main() -> int:
    p = pathlib.Path(sys.argv[1])
    prof = json.loads(p.read_text())
    nodes = {n["id"]: n for n in prof["nodes"]}
    # THE SELF TIME IS THE TIME BETWEEN A SAMPLE AND THE NEXT, MINUS THE CHILDREN'S.
    self_us = defaultdict(float)
    deltas = prof.get("timeDeltas") or []
    samples = prof.get("samples") or []
    for i, sid in enumerate(samples):
        d = deltas[i] if i < len(deltas) else 0
        self_us[sid] += max(0, d)
    # THE NAME IS THE CALL FRAME'S, AND THE COMPILER'S FRAMES ARE LONG -- SO THE LAST SEGMENT IS THE
    # DEF, AND THE SEGMENT BEFORE IT IS THE MODULE.
    rows = []
    for sid, us in self_us.items():
        n = nodes.get(sid)
        if n is None:
            continue
        cf = n.get("callFrame") or {}
        url = (cf.get("url") or "").rsplit("/", 1)[-1]
        name = cf.get("functionName") or "(anonymous)"
        rows.append((us, name, url, cf.get("lineNumber")))
    rows.sort(reverse=True)
    total = sum(r[0] for r in rows) or 1.0
    print(f"{'self%':>7} {'self ms':>9}  function")
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    for us, name, url, line in rows[:n]:
        print(f"{us / total * 100:7.2f} {us / 1000:9.2f}  {name}  [{url}:{line}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
