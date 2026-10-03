#!/usr/bin/env python3
"""Classify comment BLOCKS by archetype so the pass acts on a named population
rather than on a line count."""
import sys, os, re
from collections import Counter, defaultdict
sys.path.insert(0, os.path.dirname(__file__))
from upstream import norm

def blocks(lines):
    out = []; i = 0; n = len(lines)
    while i < n:
        if lines[i].strip().startswith('#'):
            j = k = i
            while j < n:
                if lines[j].strip().startswith('#'): k = j; j += 1
                elif lines[j].strip() == '': j += 1
                else: break
            out.append((i, k)); i = k + 1
        else: i += 1
    return out

def archetype(seg, is_file_top):
    txt = '\n'.join(seg)
    first = norm(seg[0])[:70]
    n = len(seg)
    has = lambda pat: bool(re.search(pat, txt, re.I))
    if is_file_top and n >= 15: return 'FILE HEADER'
    if has(r'\bMUTATIONS?\b.*\bM\d+\b') and has(r'\bM\d+\b'): return 'MUTATION TABLE'
    if re.search(r'^\s*#\s*=+\s*$', seg[0] or '') or has(r'SECTION [A-Z]'): return 'SECTION DIVIDER'
    if has(r'\bDEFECT \d') or has(r'\bTWO MEASURED DEFECTS') or has(r'\bREPORTED NOT FIXED'): return 'DEFECT REPORT'
    if has(r'\bTHE GATE\b') or has(r'\bGATE prints\b'): return 'GATE DESCRIPTION'
    if has(r'\bWHAT IS HERE\b') or has(r'\bALREADY PORTED\b'): return 'PORT MAP / SCOPE'
    if has(r'\bWALL\b'): return 'WALL'
    if has(r'MEASURED'): return 'MEASURED FACT'
    if n >= 15: return 'LONG PROSE (unclassified)'
    return 'SHORT'

def main():
    files = sys.argv[1:]
    arch = defaultdict(lambda: [0, 0, []])
    for p in files:
        with open(p, encoding='utf-8', errors='replace') as fh:
            lines = fh.read().split('\n')
        for (a, b) in blocks(lines):
            seg = lines[a:b+1]
            if not all(l.strip().startswith('#') for l in seg): continue
            is_top = a <= 40
            k = archetype(seg, is_top)
            arch[k][0] += 1; arch[k][1] += len(seg)
            arch[k][2].append((p.replace('.agents/slop/commentpass/before/tinybendygrad/',''), a+1, len(seg), norm(seg[0])[:60]))
    print(f"{'archetype':26s} {'blocks':>7s} {'lines':>7s}  of which >10 lines")
    T = [0, 0]
    for k, (c, l, ex) in sorted(arch.items(), key=lambda x: -x[1][1]):
        big = sum(1 for (p, a, s, t) in ex if s > 10)
        bigl = sum(s for (p, a, s, t) in ex if s > 10)
        T[0] += c; T[1] += l
        print(f'{k:26s} {c:7d} {l:7d}  {big:5d} blocks / {bigl:6d} lines')
    print(f"{'TOTAL':26s} {T[0]:7d} {T[1]:7d}")

if __name__ == '__main__':
    main()