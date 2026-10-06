#!/usr/bin/env python3
"""Final split: REFERENCED iff a committed file NAMES THE PATH, excluding census artifacts.

The task's test is "a committed file names the path". Every `.txt` path in the tree is named
by SOME committed file if census artifacts count -- `sloptxt/PLAN.tsv`, `features.json` and
`capstream/discover.json` list the whole population by construction. A census that enumerates a
set cannot be evidence about a member of it; `sloptxt/readers.py` said the same and dropped
`.md`/`.json` citation DBs. So the population of NAMING files is (c) a REGEX OVER WRITE SITES,
minus an admitted census list kept here in code, never typed as data.

EXCLUDED as census/citation (they list paths, they do not read files):
  .agents/slop/sloptxt/   .agents/slop/capstream/   .agents/slop/_cite/
  .agents/slop/txtexec/   checks/txt-owners.py

A target is REFERENCED if its repo-relative path appears in a committed file outside that list.
Otherwise it is a NEITHER candidate; the script prints every basename mention so the binding can
be read before a rename.
"""
import json
import os
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DISC = os.path.join(ROOT, ".agents/slop/capstream/discover.json")
CENSUS_PREFIX = (".agents/slop/sloptxt/", ".agents/slop/capstream/", ".agents/slop/_cite/",
                 ".agents/slop/txtexec/")
CENSUS_FILES = {"checks/txt-owners.py"}


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def is_census(f):
    return f.startswith(CENSUS_PREFIX) or f in CENSUS_FILES


def main():
    d = json.load(open(DISC))
    caps = sorted(t for t in d["targets"] if t.startswith(".agents/slop/") and d["class"][t] == "CAPTURED-STREAM")
    blob = {}
    for f in tracked():
        if is_census(f) or f.endswith(".txt"):
            continue
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 5_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" not in data:
            blob[f] = data

    ref, neither = {}, []
    for t in caps:
        tb = t.encode()
        hits = [f for f, data in blob.items() if f != t and tb in data]
        if hits:
            ref[t] = hits
        else:
            neither.append(t)

    print(f"CAPTURED-STREAM: {len(caps)}")
    print(f"  REFERENCED (path named by a committed file): {len(ref)}")
    print(f"  NEITHER (no path naming): {len(neither)}")
    print(f"  NEITHER by basename: {Counter(os.path.basename(t) for t in neither).most_common()}")
    json.dump({"referenced": {k: sorted(v) for k, v in ref.items()}, "neither": neither},
              open(os.path.join(ROOT, ".agents/slop/capstream/final_split.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
