#!/usr/bin/env python3
# elford.py -- reorder a chain of `def PREFIX<name>(` blocks so a def appears
# BEFORE its caller. bend 2.0.34 has no forward references, and the chains here
# (`Ehdr.at5` -> `at4` -> ... -> `at`) are the shape the language forces.
#
#     python3 elford.py <file> <prefix> <name1> <name2> ...
#
# Lists the names DEEPEST FIRST. Asserts every name was found and that the move
# did not change the def count -- the "a scripted block move must assert
# end > start" trap from .agents/slop/agent-core.md.

import sys, re

def main():
    path, prefix = sys.argv[1], sys.argv[2]
    names = sys.argv[3:]
    lines = open(path).read().split('\n')
    blocks = {}
    for nm in names:
        pat = 'def %s%s(' % (prefix, nm) if nm else 'def %s(' % prefix
        idxs = [k for k, l in enumerate(lines) if l.startswith(pat)]
        if not idxs:
            print('MISSING %s%s' % (prefix, nm)); sys.exit(1)
        i = idxs[-1]
        j = i + 1
        while j < len(lines) and (lines[j].startswith('  ') or lines[j].strip() == ''):
            if lines[j].strip() == '' and j + 1 < len(lines) and lines[j+1].startswith('def '):
                break
            j += 1
        blocks[nm] = (i, j)
    ndefs_before = sum(1 for l in lines if l.startswith('def '))
    start = min(v[0] for v in blocks.values())
    end = max(v[1] for v in blocks.values())
    assert start < end, 'empty span'
    new = []
    for nm in names:
        a, b = blocks[nm]
        new += lines[a:b]
    lines = lines[:start] + new + lines[end:]
    ndefs_after = sum(1 for l in lines if l.startswith('def '))
    if ndefs_before != ndefs_after:
        print('DEF COUNT CHANGED %d -> %d' % (ndefs_before, ndefs_after)); sys.exit(2)
    open(path, 'w').write('\n'.join(lines))
    print('reordered %d defs, span %d..%d, def count %d unchanged'
          % (len(names), start + 1, end, ndefs_after))

main()