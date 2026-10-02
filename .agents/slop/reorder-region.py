#!/usr/bin/env python3
"""Topologically order the top-level defs of ONE region of a .bend file.

Bend has NO forward references, so a `def X` must precede the first line that
CALLS X. `tools/reorder-bend.py` does the whole file, but it aborts on a cycle
elsewhere -- this file has a real `least_upper_dtypes` <-> `promo_dtype` cycle
that predates this unit -- so this version takes a start marker and an end marker
and rewrites only between them.

A BLOCK is a leading comment run, its `def`/`type` line, and the body up to the
next comment run; the comment run above a def belongs to THAT def, and it is the
body-below-the-line that the naive split gets wrong.

    .venv/bin/python reorder-region.py FILE.bend '# START' '# END'
"""
import re, sys

path, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith(start))
j = next(k for k, l in enumerate(lines) if k > i and l.startswith(end))
region = lines[i:j]
starts = [k for k, l in enumerate(region) if re.match(r'^(def |type )', l)]


def back(k):
    """the first line of the comment run immediately above region[k]"""
    b = k
    while b > 0 and region[b - 1].startswith('#'):
        b -= 1
    return b


heads = [back(k) for k in starts]
preamble = region[:heads[0]]
bounds = heads + [len(region)]
blocks = [region[bounds[n]:bounds[n + 1]] for n in range(len(heads))]
name = []
for n in range(len(heads)):
    dl = next(k for k in range(heads[n], heads[n] + 40) if re.match(r'^(def |type )', region[k]))
    name.append(re.match(r'^(?:def|type) ([A-Za-z_][\w.]*)', region[dl]).group(1))

names = set(name)
graph = {n: set() for n in names}
for n, b in zip(name, blocks):
    text = '\n'.join(b)
    for m in names:
        if m != n and re.search(r'(?<![\w.])' + re.escape(m) + r'\s*\(', text):
            graph[n].add(m)

out, seen, temp = [], set(), set()


def visit(n, stack):
    if n in seen:
        return
    if n in temp:
        raise SystemExit(f'cycle via {n} (from {sorted(stack)})')
    temp.add(n)
    for m in sorted(graph[n]):
        visit(m, stack | {n})
    temp.discard(n)
    seen.add(n)
    out.append(n)


for n in name:
    visit(n, set())
assert sorted(out) == sorted(names), 'a def was lost'
by = dict(zip(name, blocks))
open(path, 'w').write('\n'.join(lines[:i] + preamble + [l for n in out for l in by[n]] + lines[j:]))
print(f'{len(out)} blocks, {sum(1 for a, b in zip(name, out) if a != b)} moved')
