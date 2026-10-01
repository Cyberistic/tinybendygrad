#!/usr/bin/env python3
"""Topologically reorder the defs of a .bend file by call dependency, stably.

    python3 .agents/slop/tools/topo.py FILE [NAME ...]

Bend refuses a forward reference and the error names the CALLER, not the called,
so the message reads as if the caller were the problem. This rewrites the file
with every def placed after the defs it calls, preserving (a) the relative order
of defs that do not constrain each other and (b) each def's own comment block.
With NAMES given, only the transitive closure of those defs is moved and
everything else keeps its place; that keeps the diff to what a reviewer reads.
"""
import re, sys

path = sys.argv[1]
want = set(sys.argv[2:])
lines = open(path).read().split('\n')

CALL = re.compile(r'\b([a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)*)\s*\(')
DECL = re.compile(r'^(def|type)\s+([A-Za-z_][\w.]*)')

# index: name -> (start, end) of the def's own block, comments included
starts = [i for i, l in enumerate(lines) if DECL.match(l)]
blocks = {}
for k, s in enumerate(starts):
  e = starts[k + 1] if k + 1 < len(starts) else len(lines)
  while e - 1 > s and lines[e - 1].strip() == '':
    e -= 1
  # pull the comment block above the def into it
  st = s
  while st > 0 and lines[st - 1].startswith('#'):
    st -= 1
  blocks[DECL.match(lines[s]).group(2)] = (st, e)

names = [DECL.match(lines[s]).group(2) for s in starts]
deps = {}
for n, (st, e) in blocks.items():
  body = '\n'.join(lines[st:e])
  # drop comments so a mention in prose is not a dependency
  body = '\n'.join(l for l in lines[st:e] if not l.lstrip().startswith('#'))
  d = set()
  for c in CALL.findall(body):
    parts = c.split('.')
    for k in range(len(parts), 0, -1):
      cand = '.'.join(parts[:k])
      if cand in blocks and cand != n:
        d.add(cand)
        break
  deps[n] = d

sel = set(want) if want else set(names)
seen, stack = set(), list(sel)
while stack:
  n = stack.pop()
  if n in seen:
    continue
  seen.add(n)
  stack.extend(deps.get(n, ()))

order, done = [], set()
def visit(n):
  if n in done:
    return
  done.add(n)
  for d in deps.get(n, ()):
    if d in seen:
      visit(d)
  order.append(n)
for n in names:
  if n in seen:
    visit(n)

if not want:
  out = []
  emitted = set()
  for i, l in enumerate(lines):
    n = next((x for x in names if blocks[x][0] == i), None)
    if n is not None:
      if n in emitted:
        continue
      emitted.add(n)
      out.extend(lines[blocks[n][0]:blocks[n][1]])
      out.append('')
    elif any(blocks[x][0] < i < blocks[x][1] for x in emitted):
      continue
    else:
      out.append(l)
  out = '\n'.join(out)
else:
  # splice: remove selected blocks (in order), then insert them at the position
  # of the FIRST selected block, in dependency order
  lo = min(blocks[n][0] for n in seen)
  hi = max(blocks[n][1] for n in seen)
  inside = set()
  for n in seen:
    inside.update(range(blocks[n][0], blocks[n][1]))
  out = []
  inserted = False
  for i, l in enumerate(lines):
    if i in inside:
      if not inserted:
        for n in order:
          if n in seen:
            out.extend(lines[blocks[n][0]:blocks[n][1]])
            out.append('')
        inserted = True
      continue
    out.append(l)
out = re.sub(r'\n{3,}', '\n\n', out)
open(path, 'w').write(out)
print(f'reordered {len(seen)} defs in {path}')