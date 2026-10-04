#!/usr/bin/env python3
"""Find committed instruments that resolve a path RELATIVE TO THEMSELVES.

A literal grep for "xd1/head/" finds 96 files and MISSES the one that matters:
xd1/render-gate-oracle.py builds `<its own dir>/head` from __file__ and never
contains the string "xd1/head". A citation expressed as a path relative to the
script is invisible to a literal path grep -- this scans for it instead.
"""
import os, re, subprocess, sys

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
os.chdir(REPO)

TREE_NAMES = {"head", "pin", "work", "cur", "wt", "opstree", "MUTANT", "MUTANT2",
              "before", "CURRENT", "after", "FENCED", "tinybendygrad", "tinygrad",
              "AFTER2", "head-copy", "planted"}

files = subprocess.run(["git", "ls-files", "*.py", "*.sh"], capture_output=True,
                       text=True).stdout.split()
files = [f for f in files if not f.startswith(".agents/slop/_cleanup/")]

# matches 'name' or "name" where name is a tree, near a path-join/sys.path call
tok = re.compile(r"""['"]([A-Za-z0-9_.\-]+)['"]""")
pat = re.compile(r"sys\.path\.(?:insert|append)|os\.path\.join|shutil\.copytree|"
                 r"abspath\(__file__\)|dirname\(__file__\)")

hits = {}
for f in files:
    try:
        lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    d = os.path.dirname(f)
    for i, ln in enumerate(lines, 1):
        if not pat.search(ln):
            continue
        for m in tok.finditer(ln):
            name = m.group(1)
            if name in TREE_NAMES and os.path.isdir(os.path.join(d, name)):
                hits.setdefault(os.path.join(d, name), []).append((f, i, ln.strip()))

print(f"shadow trees reached by a SELF-RELATIVE path in a committed instrument: "
      f"{len(hits)}\n")
for tree in sorted(hits):
    print(f"{tree}")
    for f, i, ln in hits[tree][:4]:
        print(f"    {f}:{i}  {ln[:110]}")
    if len(hits[tree]) > 4:
        print(f"    ... and {len(hits[tree]) - 4} more")
    print()