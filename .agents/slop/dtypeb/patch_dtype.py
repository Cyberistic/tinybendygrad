#!/usr/bin/env python3
"""Assemble the patched dtype.bend: head (1..566) + the two pure tails.

Usage: patch_dtype.py <tree-root>   # writes <tree-root>/tinybendygrad/dtype.bend
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
HEAD_END = 566            # dtype.bend:566 is the last line before the seam header

def main():
    root = sys.argv[1]
    src = os.path.join(REPO, 'tinybendygrad', 'dtype.bend')
    lines = open(src).read().split('\n')
    assert lines[HEAD_END-1].strip() == '', repr(lines[HEAD_END-1])
    assert lines[HEAD_END].startswith('# ====='), repr(lines[HEAD_END])
    head = '\n'.join(lines[:HEAD_END])
    i64 = open(os.path.join(HERE, 'tail-i64-pure.bend.txt')).read().rstrip('\n')
    fp8 = open(os.path.join(HERE, 'tail-fp8-pure.bend.txt')).read().rstrip('\n')
    out = head + '\n\n' + i64 + '\n\n' + fp8 + '\n'
    dst = os.path.join(root, 'tinybendygrad', 'dtype.bend')
    open(dst, 'w').write(out)
    print(f'wrote {dst}  {len(out.splitlines())} lines')

main()
