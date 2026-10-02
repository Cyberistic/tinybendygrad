#!/usr/bin/env python3
"""Topologically reorder every top-level def/type in a .bend file.

Bend has NO forward references, so a `def X` must precede the first line that
CALLS X. Hand-maintaining that order is what this project keeps losing time to,
so this does it: it splits the file into blocks (a leading `#` comment run
attached to its `def`/`type`), builds a call graph by scanning each block's own
text, and emits a stable topological order that preserves the original relative
order wherever the graph does not force a change.

Only `def`, `type` and `import` lines start a block. Everything else is
attached to the block above it, so a prose section stays with its code.

    .agents/slop/tools/reorder-bend.py FILE.bend
"""
import re, sys

path = sys.argv[1]
lines = open(path).read().split('\n')

starts = []
for i, l in enumerate(lines):
    if re.match(r'^(def |type |import )', l):
        starts.append(i)

blocks = []          # (name|None, [lines...])
head = []
prev = 0
for k, i in enumerate(starts):
    # anything between the previous block and this start that is not a comment
    # run belongs to the previous block; a comment run belongs to THIS block.
    gap = lines[prev:i]
    j = 0
    while j < len(gap) and gap[j].startswith('#'):
        j += 1
    if k > 0:
        blocks[-1][1].extend(gap[:j])       # trailing comments stay above
        head.extend(gap[j:])
    else:
        head.extend(gap)
    end = starts[k+1] if k+1 < len(starts) else len(lines)
    body = lines[i:end]
    name = re.match(r'^(?:def|type) ([\w.]+)', body[0])
    blocks.append([name.group(1) if name else None, body])
    prev = end

tail = []
if blocks and lines[prev:] :
    blocks[-1][1].extend(lines[prev:])

names = {n for n, _ in blocks if n}
# the call graph: X depends on Y if Y( appears in X's block
edges = {}
for n, body in blocks:
    if n is None: continue
    txt = '\n'.join(body)
    deps = set()
    for m in re.finditer(r'\b([A-Za-z_][\w]*(?:\.[\w]+)*)\s*\(', txt):
        cand = m.group(1)
        if cand in names and cand != n:
            deps.add(cand)
    edges[n] = deps

order, state = [], {}
def visit(n, path):
    if state.get(n) == 2: return
    if state.get(n) == 1: raise SystemExit(f'cycle: {path + (n,)}')
    state[n] = 1
    for d in sorted(edges.get(n, ())):
        visit(d, path + (n,))
    state[n] = 2
    order.append(n)

for n, _ in blocks:
    if n: visit(n, ())

# stable output: keep blocks that are not `def`/`type` (None) and `import`
# where they are, and drop every named block into dependency order at the end.
imports = [b for b in blocks if b[0] is None]
named = {n: b for b in blocks if b[0]}

out = []
# the header: everything before the first import
first_import = next((i for i, l in enumerate(lines) if l.startswith('import ')), None)
if first_import is not None:
    out.extend(lines[:first_import])
    for i, l in enumerate(lines):
        if l.startswith('import '): out.append(l)

# any remaining None block is prose that was not attached; keep it in place by
# treating it as belonging to the previous emitted named block.
tail_blocks = []
for n, body in blocks:
    if n is None:
        continue
    tail_blocks.append((n, body))

# `import` lines already emitted; now emit everything in topological order but
# re-attach each block's leading comments by scanning upward in the original.
by_start = {}
for i, l in enumerate(lines):
    if re.match(r'^(def |type )', l):
        s = i
        while s > 0 and lines[s-1].startswith('#'):
            s -= 1
        m = re.match(r'^(?:def|type) ([\w.]+)', l)
        by_start[m.group(1)] = (s, i)

emitted = set()
for n in order:
    if n in emitted: continue
    emitted.add(n)
    s, i = by_start[n]
    end = next((x for x in range(i+1, len(lines))
                if re.match(r'^(def |type |import )', lines[x])), len(lines))
    out.extend(lines[s:end])

open(path, 'w').write('\n'.join(out) + '\n')
print(f'reordered {len(order)} definitions in {path}')
