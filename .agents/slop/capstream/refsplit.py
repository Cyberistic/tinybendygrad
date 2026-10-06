#!/usr/bin/env python3
"""Separate PATH references from BASENAME collisions inside the REFERENCED group.

`sloptxt/readers.py` marks a target REFERENCED when a committed code file names its
BASENAME. That is a basename shape, not a path: `e2e_negctl.sh` naming
`"$NC/runs/e2e/gate.txt"` marks `.agents/slop/fp8fix/gate.txt`, `jsfp8/gate.txt`,
`norm/gate.txt` and `opsbend-milestone/gate.txt` alike, though only one is that file.

This script recomputes the reference as the task states it -- "a committed file names
the PATH" -- by matching a PARENT-QUALIFIED SUFFIX of the target (>=2 path components,
e.g. `runs/e2e/gate.txt`, `norm/gate.txt`) in a committed code file. A target whose
only hits are bare basenames is a COLLISION candidate, to be confirmed by a per-path
grep before any rename.
"""
import json
import os
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DISC = os.path.join(ROOT, ".agents/slop/capstream/discover.json")
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")


def suffixes(t):
    parts = t.split("/")
    return ["/".join(parts[i:]) for i in range(1, len(parts))]  # >=2 components


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def main():
    d = json.load(open(DISC))
    ref = [t for t in d["targets"]
           if t.startswith(".agents/slop/") and d["class"][t] == "CAPTURED-STREAM"
           and d["reason"][t] == "REFERENCED"]
    code = [f for f in tracked() if f.endswith(CODE_EXT)]
    blob = {}
    for f in code:
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 2_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" not in data:
            blob[f] = data

    path_ref, base_only = {}, []
    for t in ref:
        sfx = suffixes(t)
        hit = None
        for f, data in blob.items():
            for s in sfx:
                if s.encode() in data and b"/" in s.encode():
                    hit = f"{f} names `{s}`"
                    break
            if hit:
                break
        if hit:
            path_ref[t] = hit
        else:
            base_only.append(t)

    print(f"REFERENCED (basename): {len(ref)}")
    print(f"  path-qualified in committed code : {len(path_ref)}")
    print(f"  basename-only (COLLISION candidates): {len(base_only)}")
    print("  by basename:", Counter(os.path.basename(t) for t in base_only).most_common())
    for t in base_only:
        print(f"    {t}   <- {d['refs'][t][0]}")
    json.dump({"path_ref": path_ref, "base_only": base_only},
              open(os.path.join(ROOT, ".agents/slop/capstream/refsplit.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
