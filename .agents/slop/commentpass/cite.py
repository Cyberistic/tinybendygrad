#!/usr/bin/env python3
"""CITATION SCAN: find comment text in the pass scope that some OTHER .bend file
repeats.  A repeated comment line is a citation -- deleting ours breaks the other
file's reference.  Report pairs, strongest first."""
import sys, os, re, glob
from collections import defaultdict

SCOPE = set(os.path.abspath(p) for p in (
    sorted(glob.glob('tinybendygrad/nn/*.bend')) + sorted(glob.glob('tinybendygrad/mixin/*.bend')) +
    sorted(glob.glob('tinybendygrad/engine/*.bend')) + sorted(glob.glob('tinybendygrad/schedule/*.bend')) +
    ['tinybendygrad/tensor.bend', 'tinybendygrad/device.bend']))

def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'^#+\s*', '', s.strip())).strip()

def toks(s):
    return set(w.lower() for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', s) if len(w) >= 4)

def main():
    outside = defaultdict(dict)   # normalized line -> {file: [linenos]}
    inside = defaultdict(list)
    for dp, dn, fn in os.walk('tinybendygrad'):
        for f in fn:
            if not f.endswith('.bend'): continue
            p = os.path.join(dp, f)
            with open(p, encoding='utf-8', errors='replace') as fh:
                for i, l in enumerate(fh.read().split('\n'), 1):
                    if not l.strip().startswith('#'): continue
                    nz = norm(l)
                    if len(nz) < 20: continue
                    (inside[nz] if os.path.abspath(p) in SCOPE else outside[nz]) \
                        .append((p, i)) if os.path.abspath(p) in SCOPE else outside[nz].setdefault(p, []).append(i)
    # exact repeats
    exact = 0
    for nz, hits in inside.items():
        if nz in outside:
            exact += 1
            print(f'EXACT  scope: {hits[0][0]}:{hits[0][1]}  <- also in ' +
                  ', '.join(f'{p}:{v[0]}' for p, v in outside[nz].items()))
            print(f'       {nz[:120]}')
    # fuzzy repeats
    tok = {nz: toks(nz) for nz in inside}
    idx = defaultdict(list)
    for nz, t in outside.items():
        for w in t: idx[w].append(nz)
    print()
    print('--- fuzzy (Jaccard >= 0.55 on tokens, >=4 shared tokens) ---')
    n = 0
    for nz, t in tok.items():
        if len(t) < 4: continue
        cnt = defaultdict(int)
        for w in t:
            for o in idx.get(w, ()): cnt[o] += 1
        for o, sh in cnt.items():
            ot = toks(o)
            j = sh / len(t | ot)
            if j >= 0.55:
                n += 1
                print(f'  sim={j:.2f}  ours {inside[nz][0][0]}:{inside[nz][0][1]}  '
                      f'cited {", ".join(f"{p}:{v[0]}" for p, v in outside[o].items())}')
                print(f'     ours : {nz[:120]}')
                print(f'     cited: {o[:120]}')
    print(f'exact={exact} fuzzy={n}')

if __name__ == '__main__':
    main()