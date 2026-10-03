#!/usr/bin/env python3
"""TODO(p*) census over the WHOLE tree and over the pass scope."""
import re, sys, glob, os
SCOPE = (sorted(glob.glob('tinybendygrad/nn/*.bend')) + sorted(glob.glob('tinybendygrad/mixin/*.bend')) +
         sorted(glob.glob('tinybendygrad/engine/*.bend')) + sorted(glob.glob('tinybendygrad/schedule/*.bend')) +
         ['tinybendygrad/tensor.bend', 'tinybendygrad/device.bend'])
def scan(paths, tag):
    tot = 0; per = {}
    for p in paths:
        with open(p, encoding='utf-8', errors='replace') as fh:
            n = len(re.findall(r'TODO\(p\d+\)', fh.read()))
        if n: per[p] = n
        tot += n
    print(f'--- {tag}: {len(per)} files, {tot} TODO(p*) markers')
    for k, v in sorted(per.items()):
        print(f'   {v:5d} {k}')
    return tot
if __name__ == '__main__':
    base = sys.argv[1] if len(sys.argv) > 1 else ''
    if base:
        allp = [os.path.join(dp, f) for dp, dn, fn in os.walk(base) for f in fn if f.endswith('.bend')]
        sc = [os.path.join(base, os.path.relpath(p, '.')) for p in SCOPE]
    else:
        allp = [dp + '/' + f for dp, dn, fn in os.walk('tinybendygrad') for f in fn if f.endswith('.bend')]
        sc = SCOPE
    t = scan(allp, 'WHOLE TREE')
    scan(sc, 'PASS SCOPE')
    print('TOTAL', t)