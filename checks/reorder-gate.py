#!/usr/bin/env python3
"""Topologically reorder the `t_*` gate functions in a .bend file.

Bend has no forward references, so every `def X` must precede the first line
that CALLS X. This moves only the `t_*` IO functions, keeping their preceding
comment block attached, and places them in dependency order immediately before
`def main`. Pure helpers (`def name` without a leading `t_`) are left alone.

Usage: reorder-gate.py <file.bend>
"""
import re, sys

path = sys.argv[1]
src = open(path).read()

# split into (leading-comment + def) chunks at every top-level `def `/`type `
starts = [m for m in re.finditer(r'^(def |type |import |# =====)', src, re.M)]
chunks, prev = [], 0
for m in starts:
    if m.start() > prev:
        chunks.append(src[prev:m.start()])
    chunks.append(None)  # placeholder
    prev = m.start()
# rebuild as (prefix, name, body)
items = []
pos = 0
for m in starts:
    items.append(src[pos:m.start()])
    items.append(m.group(0) + src[m.end():src.index('\n', m.end())])
    pos = src.index('\n', m.end()) + 1
items.append(src[pos:])

groups = []
cur = []
i = 0
while i < len(items):
    if i + 1 < len(items) and items[i+1].startswith('def '):
        nm = re.match(r'def ([\w.]+)\(', items[i+1]).group(1)
        cur.append((items[i], nm, items[i+1]))
        i += 2
    else:
        if cur: groups.append(('blk', cur)); cur = []
        groups.append(('raw', items[i]))
        i += 1
if cur: groups.append(('blk', cur))

# gather every def name -> its calls
defs = {}
for kind, g in groups:
    if kind != 'blk': continue
    for pre, nm, sig in g:
        defs[nm] = None
# second pass: body text is the following raw/def chunks, so just use the whole
# source for call extraction -- a name only counts if it appears as a call.
call_re = {nm: set() for nm in defs}
for nm in defs:
    pat = re.compile(r'\b%s\s*\(' % re.escape(nm))
    for other in defs:
        if other == nm: continue
        # cheap: does the region between this def's signature line and the next
        # top-level `def ` mention the name?
        pass

# simpler and reliable: locate each t_ def's span by line
lines = src.split('\n')
spans = {}
for idx, l in enumerate(lines):
    m = re.match(r'def (t_\w+)\(', l)
    if m:
        j = idx + 1
        while j < len(lines) and not (lines[j].startswith('def ') or lines[j].startswith('type ') or lines[j].startswith('# =====')):
            j += 1
        spans[m.group(1)] = (idx, j)

for nm, (a, b) in spans.items():
    body = '\n'.join(lines[a:b])
    for other in spans:
        if other == nm: continue
        if re.search(r'\b%s\s*\(' % re.escape(other), body):
            call_re[nm].add(other)

# topological sort: callees first
order, seen = [], set()
def visit(n, stack=()):
    if n in seen: return
    assert n not in stack, f'cycle {n}'
    for c in sorted(call_re[n]):
        visit(c, stack + (n,))
    seen.add(n); order.append(n)
for n in sorted(spans):
    visit(n)

# extract the moved blocks (with their leading comment) and rebuild the file
moved_src = []
for n in order:
    a, b = spans[n]
    # walk back over the comment block
    s = a
    while s > 0 and lines[s-1].startswith('#'):
        s -= 1
    moved_src.append((s, b, '\n'.join(lines[s:b]) + '\n'))
new_lines = list(lines)
for s, e, _ in sorted(moved_src, reverse=True):
    del new_lines[s:e]
tail = '\n'.join(new_lines)
ins = tail.find('def main() -> IO(Unit):')
assert ins > 0
tail = tail[:ins] + '\n'.join(t[2] for t in moved_src) + '\n' + tail[ins:]
open(path, 'w').write(tail)
print('reordered:', ', '.join(order))
