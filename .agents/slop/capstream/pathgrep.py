#!/usr/bin/env python3
"""Literal per-path grep: which CAPTURED-STREAM `.txt` does a committed file NAME BY PATH?

The task's REFERENCED test is "a committed file names the PATH". This scans EVERY committed
file's bytes (not just code, not just basenames) for the target's repo-relative path. A target
with no full-path hit is a NEITHER candidate; the script then reports every basename mention it
has, with the naming line, so the binding can be read and the rename judged safe or not.
"""
import json
import os
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DISC = os.path.join(ROOT, ".agents/slop/capstream/discover.json")


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def main():
    d = json.load(open(DISC))
    caps = [t for t in d["targets"] if t.startswith(".agents/slop/") and d["class"][t] == "CAPTURED-STREAM"]
    files = tracked()
    blob = {}
    for f in files:
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 5_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" not in data:
            blob[f] = data

    path_named, neither = [], []
    for t in caps:
        tb = t.encode()
        hits = [f for f, data in blob.items() if f != t and tb in data]
        (path_named if hits else neither).append(t)

    print(f"CAPTURED-STREAM: {len(caps)}")
    print(f"  named BY FULL PATH in a committed file: {len(path_named)}")
    print(f"  no full-path mention (NEITHER candidates): {len(neither)}")
    print()
    out = {}
    for t in neither:
        base = os.path.basename(t).encode()
        mentions = []
        for f, data in blob.items():
            if f == t or base not in data:
                continue
            for i, line in enumerate(data.splitlines(), 1):
                if base in line:
                    mentions.append(f"{f}:{i}  {line[:120].decode('utf-8', 'replace')}")
        out[t] = mentions
        print(f"== {t}  (reason was {d['reason'][t]})")
        for m in mentions[:4]:
            print(f"     {m}")
        if not mentions:
            print("     (no basename mention in any committed file)")
    json.dump({"path_named": path_named, "neither": neither, "mentions": out},
              open(os.path.join(ROOT, ".agents/slop/capstream/pathgrep.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
