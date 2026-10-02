#!/usr/bin/env python3
"""Audit the classifier's error rate by dumping a sample for MANUAL inspection."""
import sys, os, re, random
sys.path.insert(0, os.path.dirname(__file__))
from upstream import norm, content_tokens, classify_line, load_corpus

upfiles, uper, uglobal = load_corpus()

def audit(files, n=60, seed=7, minlen=25):
    rng = random.Random(seed)
    ours, ups = [], []
    for p in files:
        with open(p, encoding='utf-8', errors='replace') as fh:
            for i, l in enumerate(fh.read().split('\n')):
                if not l.strip().startswith('#'): continue
                nz = norm(l)
                if len(nz) < minlen: continue
                (ups if classify_line(nz, uglobal) else ours).append((p, i+1, nz))
    print(f'# sampled {n} of {len(ours)} "OURS" lines (len>={minlen}), seed {seed}')
    for (p, i, t) in rng.sample(ours, min(n, len(ours))):
        print(f'OURS {os.path.basename(p)}:{i}\n   {t[:150]}')
    print()
    print(f'# ALL {len(ups)} "UPSTREAM" lines (len>={minlen})')
    for (p, i, t) in ups:
        print(f'UP   {os.path.basename(p)}:{i}\n   {t[:150]}')

if __name__ == '__main__':
    audit(sys.argv[1:])