#!/usr/bin/env python3
"""Collapse N CONSECUTIVE IDENTICAL comment blocks into one.

`reorder-bend.py` walked backwards over the comment run above each `def`, so a
comment run that sat above a def but below the previous one was emitted once
per def between them, and running the tool repeatedly MULTIPLIED the file (a
measured 147913 lines from an 1873-line source). The damage is exactly
recoverable: consecutive identical comment runs are redundant, and collapsing
them is idempotent.

    .agents/slop/tools/dedupe-comments.py FILE.bend
"""
import sys

path = sys.argv[1]
lines = open(path).read().split('\n')
out, i, removed = [], 0, 0
while i < len(lines):
    if lines[i].startswith('#'):
        j = i
        while j < len(lines) and lines[j].startswith('#'):
            j += 1
        blk = lines[i:j]
        # how many more identical runs follow immediately?
        k = j
        while k + len(blk) <= len(lines) and lines[k:k+len(blk)] == blk:
            k += len(blk)
            removed += len(blk)
        out.extend(blk)
        i = k
    else:
        out.append(lines[i])
        i += 1
open(path, 'w').write('\n'.join(out))
print(f'{path}: {len(lines)} -> {len(out)} lines ({removed} duplicated comment lines removed)')
