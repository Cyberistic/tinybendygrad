#!/usr/bin/env python3
"""Dump comment blocks of a file, for authoring replacements."""
import sys, json

def blocks(lines):
    out = []; i = 0; n = len(lines)
    while i < n:
        if lines[i].strip().startswith('#'):
            j = k = i
            while j < n:
                if lines[j].strip().startswith('#'): k = j; j += 1
                elif lines[j].strip() == '': j += 1
                else: break
            out.append((i, k + 1)); i = k + 1
        else: i += 1
    return out

def main():
    path = sys.argv[1]; minsz = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().split('\n')
    for (a, b) in blocks(lines):
        seg = lines[a:b]
        if not all(l.strip().startswith('#') for l in seg): continue
        if len(seg) < minsz: continue
        print(f'@@@ {a+1}-{b} ({len(seg)})')
        for i, l in enumerate(seg, a + 1):
            print(f'{i:5d}| {l}')

if __name__ == '__main__':
    main()