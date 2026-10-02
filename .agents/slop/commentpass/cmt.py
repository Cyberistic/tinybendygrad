#!/usr/bin/env python3
"""Comment measurement for the realign pass.

A COMMENT LINE is a line whose first non-space character is '#'.
Trailing '#' comments are counted separately (see trailing()).
Blocks are maximal runs of comment lines separated only by blank lines,
so a header written as paragraphs is ONE block -- that is what a reader
sees as one wall.
"""
import sys, os, json, re
from collections import Counter

def is_comment(line):
    s = line.strip()
    return s.startswith('#')

def blocks(lines):
    """Yield (start_idx, end_idx_exclusive, [line_idx...]) over comment blocks."""
    out = []
    i = 0
    n = len(lines)
    while i < n:
        if is_comment(lines[i]):
            j = i
            k = i
            # absorb: comment lines, with blank lines allowed ONLY if another
            # comment line follows within the run (so trailing blanks excluded).
            while j < n:
                if is_comment(lines[j]):
                    k = j
                    j += 1
                elif lines[j].strip() == '':
                    j += 1
                else:
                    break
            out.append((i, k + 1, list(range(i, k + 1))))
            i = k + 1
        else:
            i += 1
    return out

def analyze(path):
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    if lines and lines[-1] == '':
        lines = lines[:-1]
    cl = [i for i, l in enumerate(lines) if is_comment(l)]
    trailing = [i for i, l in enumerate(lines) if '#' in l and not is_comment(l)]
    bl = blocks(lines)
    return {
        'path': path,
        'total': len(lines),
        'comment_lines': len(cl),
        'trailing': len(trailing),
        'blocks': [{'start': a, 'end': b, 'size': b - a} for (a, b, _) in bl],
        'lines': lines,
    }

def main():
    files = sys.argv[1:]
    grand = Counter()
    rows = []
    for p in files:
        a = analyze(p)
        sizes = [b['size'] for b in a['blocks']]
        hist = Counter(sizes)
        rows.append((p, a, sizes, hist))
        grand['total'] += a['total']
        grand['comment'] += a['comment_lines']
        grand['trailing'] += a['trailing']
        grand['blocks'] += len(a['blocks'])
        for s in sizes:
            grand['bsize_' + (f'{s}' if s < 10 else '10+')] += 1
    print(f"{'file':52s} {'tot':>7s} {'cmt':>6s} {'tr':>4s} {'blk':>5s}  max  >4  >6  >10  >20")
    for (p, a, sizes, hist) in rows:
        print(f"{p.replace('tinybendygrad/',''):52s} {a['total']:7d} {a['comment_lines']:6d} "
              f"{a['trailing']:4d} {len(a['blocks']):5d} {max(sizes) if sizes else 0:4d} "
              f"{sum(1 for s in sizes if s>4):4d} {sum(1 for s in sizes if s>6):4d} "
              f"{sum(1 for s in sizes if s>10):4d} {sum(1 for s in sizes if s>20):4d}")
    print()
    print('TOTAL lines', grand['total'], ' comment-only lines', grand['comment'],
          ' trailing', grand['trailing'], ' blocks', grand['blocks'])
    allsizes = []
    for (p, a, sizes, hist) in rows:
        allsizes += sizes
    print('block size histogram (size:count):')
    for s in sorted(set(allsizes)):
        print(f"  {s:4d}: {allsizes.count(s)}")
    print('blocks with size>N:')
    for N in (2, 3, 4, 5, 6, 8, 10, 15, 20, 30):
        over = [s for s in allsizes if s > N]
        print(f"  >{N:3d}: {len(over):5d} blocks, {sum(over):7d} lines "
              f"({100.0*sum(over)/max(1,grand['comment']):5.1f}% of comment volume)")

if __name__ == '__main__':
    main()