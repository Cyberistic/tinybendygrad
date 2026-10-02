#!/usr/bin/env python3
"""TODO(p*) census, compared BEFORE vs AFTER for a set of files.  Two levels:
 - the marker COUNT (must be identical)
 - the marker TEXT (each `TODO(pN) <what>` on one logical line, whitespace-normalised)
"""
import re, sys, glob, os
SNAP = '.agents/slop/commentpass/before/'
SCOPE = (sorted(glob.glob('tinybendygrad/nn/*.bend')) + sorted(glob.glob('tinybendygrad/mixin/*.bend')) +
         sorted(glob.glob('tinybendygrad/engine/*.bend')) + sorted(glob.glob('tinybendygrad/schedule/*.bend')) +
         ['tinybendygrad/tensor.bend', 'tinybendygrad/device.bend'])

def txt(path):
    """Each TODO(pN) plus the rest of its comment line, whitespace-normalised."""
    out = []
    for l in open(path, encoding='utf-8', errors='replace'):
        if 'TODO(p' not in l: continue
        s = l.strip().lstrip('#').strip()
        s = re.sub(r'\s+', ' ', s)
        out.append(s)
    return out

def main():
    bad = 0
    tot_b = tot_a = 0
    for p in SCOPE:
        sb = SNAP + p
        if not os.path.exists(sb): continue
        b = open(sb, encoding='utf-8', errors='replace').read()
        a = open(p, encoding='utf-8', errors='replace').read()
        cb = len(re.findall(r'TODO\(p\d+\)', b))
        ca = len(re.findall(r'TODO\(p\d+\)', a))
        tot_b += cb; tot_a += ca
        tb, ta = txt(sb), txt(p)
        if cb != ca or tb != ta:
            bad += 1
            print(f'MISMATCH {p}: count {cb} -> {ca}')
            for x in tb:
                if tb.count(x) > ta.count(x):
                    print(f'   LOST: {x[:100]}')
            for x in ta:
                if ta.count(x) > tb.count(x):
                    print(f'   NEW : {x[:100]}')
    print(f'PASS SCOPE: TODO(p*) markers {tot_b} -> {tot_a}; files with a text or count mismatch: {bad}')
    wb = sum(len(re.findall(r'TODO\(p\d+\)', open(SNAP + p, encoding='utf-8', errors='replace').read()))
             for p in SCOPE if os.path.exists(SNAP + p))
    wa = sum(len(re.findall(r'TODO\(p\d+\)', open(p, encoding='utf-8', errors='replace').read())) for p in SCOPE)
    tree_b = tree_a = 0
    for dp, dn, fn in os.walk('tinybendygrad'):
        for f in fn:
            if not f.endswith('.bend'): continue
            q = os.path.join(dp, f)
            tree_a += len(re.findall(r'TODO\(p\d+\)', open(q, encoding='utf-8', errors='replace').read()))
            sq = SNAP + q
            if os.path.exists(sq):
                tree_b += len(re.findall(r'TODO\(p\d+\)', open(sq, encoding='utf-8', errors='replace').read()))
    print(f'WHOLE TREE (snapshot-covered files only): {tree_b} -> {tree_a}; now: {tree_a} across the live tree')

if __name__ == '__main__':
    main()