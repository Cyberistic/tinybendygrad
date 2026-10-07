#!/usr/bin/env python3
"""RECOVERABILITY of the absent subjects, by DISCOVERY over ALL history.

The naive test is `git cat-file -s 371cc64c9^:<path>`, and it answers "no blob" for 11 of 12 --
because these files were never at those paths before the sweep. They were MOVED into `checks/`
by `3f0e70ff1` and then swept. So the honest question is not "was it at this path" but "does a
blob of this BASENAME exist at ANY rev, anywhere", which is a search over history and not a
lookup at one rev. Both are reported, and the second is the one that decides recoverability.
"""
import collections
import re
import subprocess
import sys

PATHS = [ln.strip() for ln in open(sys.argv[1]) if ln.strip()]


def git(*a):
    return subprocess.run(("git",) + a, capture_output=True, text=True).stdout


hist = git("log", "--all", "--format=%H", "--name-status", "--no-renames").splitlines()
# (basename, path, status) triples, in commit order
triples = []
for ln in hist:
    parts = ln.split("\t")
    if len(parts) >= 2 and parts[0][:1] in ("A", "D", "M"):
        triples.append((parts[1].rsplit("/", 1)[-1], parts[1], parts[0]))

by_base = collections.defaultdict(set)
for base, path, _ in triples:
    by_base[base].add(path)

print(f"{'PATH':34s} {'BASENAME-SEEN-IN-HISTORY':22s} VERDICT")
recoverable, gone = [], []
for p in PATHS:
    base = p.rsplit("/", 1)[-1]
    hist_paths = sorted(by_base.get(base, ()))
    # a blob must EXIST, not merely have been named: `git cat-file -s` against the newest rev
    # that touched each historical path.
    found = []
    for hp in hist_paths:
        out = git("log", "--all", "--format=%H", "-1", "--", hp).strip()
        if not out:
            continue
        size = git("cat-file", "-s", f"{out}:{hp}").strip()
        if size.isdigit() and int(size) > 0:
            found.append(f"{hp}@{out[:9]}={size}B")
    if found:
        recoverable.append(p)
        print(f"{p:34s} {str(len(hist_paths)):22s} RECOVERABLE  {found[0]}")
    else:
        gone.append(p)
        print(f"{p:34s} {str(len(hist_paths)):22s} NO-BLOB-ANYWHERE"
              + (f"  (paths ever: {hist_paths[:3]})" if hist_paths else "  (basename never appears)"))
print(f"\nRECOVERABLE {len(recoverable)} / {len(PATHS)}   UNRECOVERABLE {len(gone)} / {len(PATHS)}")
if gone:
    print("UNRECOVERABLE, named:")
    for g in gone:
        print(f"  {g}")