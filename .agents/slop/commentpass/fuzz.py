#!/usr/bin/env python3
"""FALSE-NEGATIVE probe for the upstream-comment classifier.

For every bend comment line the strict classifier called OURS, find the most
similar Python COMMENT line in the corresponding tinygrad/*.py and report the
distribution of best similarity.  A high-similarity population means the
strict test missed reworded/reindented upstream comments.
"""
import sys, os, re, random
from collections import Counter, defaultdict
sys.path.insert(0, os.path.dirname(__file__))
from upstream import norm, content_tokens, classify_line, load_corpus

def toks(s):
    return set(w.lower() for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', s) if len(w) >= 3)

def main():
    files = sys.argv[1:]
    upfiles, uper, _ = load_corpus(mode='comments')
    # per-upstream-file comment line token sets
    per = {}
    for p in upfiles:
        with open(p, encoding='utf-8', errors='replace') as fh:
            raw = fh.read().split('\n')
        ls = [norm(l) for l in raw if l.strip().startswith('#')]
        per[p] = [(l, toks(l)) for l in ls if len(content_tokens(l)) >= 3]
    # inverted index over all upstream comment lines
    idx = defaultdict(list)
    allpairs = []
    for p, ls in per.items():
        for i, (l, t) in enumerate(ls):
            allpairs.append((p, l, t))
            for w in t:
                idx[w].append(len(allpairs) - 1)
    hits = []
    shown = 0
    for bf in files:
        base = os.path.basename(bf)
        guess = 'tinygrad/' + base.replace('.bend', '.py')
        cands = [p for p in upfiles if os.path.basename(p) == base[:-5] + '.py'] or [guess]
        candpairs = [(p, l, t) for (p, l, t) in allpairs if p in cands]
        if not candpairs: 
            print(f'NO UPSTREAM FILE for {bf}')
            continue
        with open(bf, encoding='utf-8', errors='replace') as fh:
            for i, line in enumerate(fh.read().split('\n')):
                if not line.strip().startswith('#'): continue
                nz = norm(line)
                if len(nz) < 20 or len(content_tokens(nz)) < 3: continue
                if classify_line(nz, 'x' * (len(nz) + 1)): continue  # skip strict hits
                tt = toks(nz)
                if not tt: continue
                best, bestl = 0.0, None
                cnt = Counter()
                for w in tt:
                    for (p, l, t) in candpairs:
                        pass
                for (p, l, t) in candpairs:
                    inter = len(tt & t)
                    if inter < 2: continue
                    j = inter / len(tt | t)
                    if j > best: best, bestl = j, l
                hits.append((best, bf, i + 1, nz, bestl))
    hits.sort(key=lambda x: -x[0])
    buckets = Counter()
    for (b, *_ ) in hits:
        buckets[f'{int(b*10)/10:.1f}'] += 1
    print(f'probed {len(hits)} bend comment lines that the STRICT test called OURS')
    print('best-similarity-to-an-upstream-COMMENT-line histogram (Jaccard on tokens):')
    for k in sorted(buckets, reverse=True):
        print(f'  {k}: {buckets[k]}')
    print()
    print('top 40 most similar pairs -- INSPECT THESE for reworded upstream comments:')
    for (b, bf, ln, nz, bestl) in hits[:40]:
        if b < 0.45: break
        print(f'  sim={b:.2f} {os.path.basename(bf)}:{ln}\n    bend: {nz[:130]}\n    py  : {(bestl or "")[:130]}')

if __name__ == '__main__':
    main()