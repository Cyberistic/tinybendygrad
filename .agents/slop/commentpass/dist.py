#!/usr/bin/env python3
"""Authoritative distribution: comment-only blocks (a block never absorbs a code
line), over the pass scope, from the BEFORE snapshot."""
import sys, os, glob
sys.path.insert(0, os.path.dirname(__file__))
from dump import blocks

SNAP = '.agents/slop/commentpass/before/tinybendygrad/'
FILES = (sorted(glob.glob(SNAP + 'nn/*.bend')) + sorted(glob.glob(SNAP + 'mixin/*.bend')) +
         sorted(glob.glob(SNAP + 'engine/*.bend')) + sorted(glob.glob(SNAP + 'schedule/*.bend')) +
         [SNAP + 'tensor.bend', SNAP + 'device.bend'])

sizes = []
per = []
for p in FILES:
    L = open(p, encoding='utf-8', errors='replace').read().split('\n')
    s = []
    for (a, e) in blocks(L):
        seg = L[a:e]
        if all(x.strip().startswith('#') for x in seg):
            s.append(len(seg))
    sizes += s
    per.append((p, len(L), len(s), s))

print(f"{'file':34s}{'lines':>7s}{'cmt':>7s}{'blk':>5s}{'>=5':>6s}{'>=10':>6s}{'>=15':>6s}{'>=25':>6s}{'>=50':>6s}")
for (p, n, nb, s) in per:
    cl = sum(1 for l in open(p, encoding='utf-8', errors='replace') if l.strip().startswith('#'))
    f = lambda k: sum(1 for x in s if x >= k)
    print(f"{p.replace(SNAP,''):34s}{n:7d}{cl:7d}{nb:5d}{f(5):6d}{f(10):6d}{f(15):6d}{f(25):6d}{f(50):6d}")
tot_lines = sum(p[1] for p in per); tot_cmt = sum(sizes)
print(f"{'TOTAL':34s}{tot_lines:7d}{tot_cmt:7d}{len(sizes):5d}"
      f"{sum(1 for x in sizes if x>=5):6d}{sum(1 for x in sizes if x>=10):6d}"
      f"{sum(1 for x in sizes if x>=15):6d}{sum(1 for x in sizes if x>=25):6d}{sum(1 for x in sizes if x>=50):6d}")
print()
print('comment lines inside blocks of size >= N (the deletable mass):')
for k in (3, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 75, 100):
    over = [x for x in sizes if x >= k]
    print(f'  >= {k:3d}: {len(over):4d} blocks, {sum(over):6d} lines, '
          f'{100.0*sum(over)/tot_cmt:5.1f}% of all comment lines, '
          f'{100.0*sum(over)/len(over) if over else 0:5.1f}% of the file\'s comment mass in one block')
print()
print('block-size histogram:')
from collections import Counter
c = Counter(sizes)
for k in sorted(c): print(f'  {k:4d}: {c[k]}')