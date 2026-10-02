#!/usr/bin/env python3
"""rebase-nameprobe.py -- for each port, grep the whole slop tree for its OWN row names, so
the oracle is FOUND BY ITS OUTPUT rather than by its filename."""
import json, pathlib, re, subprocess, sys
HERE = pathlib.Path(__file__).resolve().parent
SLOP = HERE
data = json.loads((HERE / "rebase" / "portrows.json").read_text())
skip = re.compile(r"(hdrbase|__pycache__|rebase/portrows|\.bend\.rows|oracles/)")
for port, info in data.items():
    names = info["rows"]
    # pick 6 names that are LONG (so a hit is a real claim, not a prefix collision)
    probe = sorted(names, key=lambda n: -len(n))[:40]
    probe = probe[::max(1, len(probe)//6)][:6]
    found = {}
    for n in probe:
        r = subprocess.run(["grep", "-rl", "--", n, "--include=*.py", "--include=*.sh", "."],
                           cwd=SLOP, capture_output=True, text=True)
        for f in r.stdout.split():
            if skip.search(f): continue
            found.setdefault(f, []).append(n)
    print(f"\n=== {port}  ({len(names)} rows)")
    for f, ns in sorted(found.items()):
        print(f"    {f}   <- {', '.join(sorted(set(ns))[:4])}")
    if not found:
        print("    NOTHING IN slop NAMES THESE ROWS")
