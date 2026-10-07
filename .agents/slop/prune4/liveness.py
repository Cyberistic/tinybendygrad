#!/usr/bin/env python3
"""Which unit dirs are being written RIGHT NOW? mtime of the newest file inside.

The task names bendperf, midrun, twopass "and three others" as live. A prune that
deletes a running unit's scratch destroys work. So the live set is DISCOVERED from
mtimes, not from the prompt's list: a dir whose newest file is younger than
WINDOW minutes is LIVE and is excluded wholesale.

Caveat measured here: mtime says when a file was WRITTEN, not whether a process
holds it. Both are inferences; neither is proof. See REPORT.md sec.7.
"""
import os, sys, time, json

ROOT = ".agents/slop"
WINDOW = float(sys.argv[1]) if len(sys.argv) > 1 else 60.0
now = time.time()

live, rows = [], []
for e in sorted(os.scandir(ROOT), key=lambda e: e.name):
    newest, nfiles = 0.0, 0
    stack = [e.path]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except OSError:
            continue
        for x in entries:
            try:
                st = x.stat(follow_symlinks=False)
            except OSError:
                continue
            newest = max(newest, st.st_mtime)
            if x.is_dir(follow_symlinks=False):
                stack.append(x.path)
            else:
                nfiles += 1
    age = (now - newest) / 60.0
    rows.append((age, nfiles, e.name))
    if newest and age <= WINDOW:
        live.append((age, nfiles, e.name))

rows.sort()
print(f"# newest-file age in minutes, {len(rows)} entries, window={WINDOW:g} min")
print("LIVE (excluded from pruning):")
for age, nf, name in live:
    print(f"  {age:7.1f} min  {nf:>4} files  {name}")
print("\nNEXT 12 (coldest-written recent work):")
for age, nf, name in rows[len(live):len(live)+12]:
    print(f"  {age:7.1f} min  {nf:>4} files  {name}")