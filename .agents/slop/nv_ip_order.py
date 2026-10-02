#!/usr/bin/env python3
"""
nv_ip_order.py -- topologically reorder the TOP-LEVEL defs of a .bend file.

Bend has no forward references, so every def must sit above its callers. Adding
a def in the wrong place is a compile error that costs a cycle, and this file
has enough small folds that it happened a dozen times. This moves defs until no
def calls a later one, preserving the relative order of everything already
correct (a stable topological sort, so a clean file is left ALONE).

    python3 .agents/slop/nv_ip_order.py tinybendygrad/runtime/support/nv/ip.bend

Comments immediately preceding a def travel with it. `type` decls travel too.
Any def it cannot order is reported and the file is left untouched.
"""
import re, sys

DEF = re.compile(r'^(def|type|law)\s')


def blocks(lines):
  """split into (kind, start, end) blocks: a header block up to the next header"""
  heads = [i for i, l in enumerate(lines) if DEF.match(l)]
  if not heads:
    return []
  out = []
  for k, h in enumerate(heads):
    e = heads[k + 1] if k + 1 < len(heads) else len(lines)
    c = h
    while c > 0 and lines[c - 1].lstrip().startswith('#'):
      c -= 1
    out.append((c, e, lines[h]))
  return out


def indented(lines, e, h):
  """the indented body lines after a header, up to the next def."""
  j = h + 1
  while j < e and (lines[j].startswith(' ') or lines[j] == ''):
    j += 1
  return lines[h + 1:j]


def oneline_tail(lines, h):
  """the body of a ONE-LINE `def ...: expr` -- everything after the FIRST colon.
  Without it `def bump(h: Bool, +n: U32) -> U32: Bool.pick(...)` has an EMPTY body,
  its callees are invisible, and the pass reports a cycle for a straight chain.
  A `type X is Data:` has a colon too and its body is the field line, which is
  NOT a one-line tail -- so a `type` returns ''."""
  if not lines[h].startswith('def '):
    return ''
  return lines[h].split(':', 1)[1] if ':' in lines[h] else ''


def scan_text(lines, h, e):
  return '\n'.join(([oneline_tail(lines, h)] if oneline_tail(lines, h).strip() else [])
                    + indented(lines, e, h))


def callees(text):
  names = set(re.findall(r'\b([a-zA-Z_][A-Za-z0-9_.]*)\s*\(', text))
  for op in ('def', 'type', 'law', 'match', 'case', 'do', 'import', 'return'):
    names.discard(op)
  # drop `Type.method(` heads that are really a local def's own prefix
  return names


def main(path):
  src = open(path).read()
  lines = src.split('\n')
  bs = blocks(lines)
  if not bs:
    print('no defs'); return
  # PREAMBLE. `blocks` walks leading comments backwards from the first header,
  # which swallows `import ...` lines and the `# --- GENERATED ... ---` markers
  # into the first def's comment block -- and on the first run of this script
  # that DELETED both, so the file stopped typechecking with "a declared
  # constructor (unknown: Nil)" and no `import Base` to explain it. The
  # preamble is everything before the first header's leading-comment run, and it
  # is copied verbatim.
  first = bs[0][0]
  pre = lines[:first]
  defs = {}
  order = []
  for c, e, head in bs:
    nm = head.split()[1].split('(')[0].rstrip(':')
    h = c
    while lines[h] != head:
      h += 1
    # `chunk` is the ORIGINAL text -- header line plus its indented body.  The
    # first version rebuilt the chunk from `body()` and so re-emitted a one-line
    # def's tail as a separate line, which is `def Cn.of(...)` followed by
    # `String, v: U32) -> Cn:`.  The split is used only to FIND callees.
    defs[nm] = (c, e, head, lines[c:h + 1] + indented(lines, e, h))
    order.append(nm)
  h_of = {}
  for nm in order:
    c, e, head, _ = defs[nm]
    hh = c
    while lines[hh] != head:
      hh += 1
    h_of[nm] = hh
  text = {}
  for nm in order:
    c, e, head, _ = defs[nm]
    text[nm] = '\n'.join(lines[c:e])

  # does `nm` call `other`?  A dotted callee `a.b(` counts as a call on `a.b`.
  deps = {}
  for nm in order:
    body_txt = scan_text(lines, h_of[nm], defs[nm][1])
    hit = set()
    for cand in order:
      if cand == nm:
        continue
      if re.search(r'\b' + re.escape(cand) + r'\s*\(', body_txt):
        hit.add(cand)
      # a def that only APPEARS (no call) still has to be above its user when it
      # is a `def` -- Bend resolves names in order, so `const_name_n(v: U32) -> U32:
      # const_name_n.go(...)` must follow `const_name_n.go`.
    deps[nm] = hit

  # stable topological sort, ties broken by current position
  out, seen = [], set()
  changed = True
  guard = 0
  while len(out) < len(order) and guard < len(order) * len(order):
    guard += 1
    before = len(out)
    for nm in order:
      if nm in seen:
        continue
      if all(d in seen for d in deps[nm]):
        out.append(nm); seen.add(nm)
    # `before`, NOT `len(out)`: comparing against len(out) after the for loop
    # is always equal, so the loop stalled after ONE pass and reported a cycle
    # for a straight-line chain.  Measured, the hard way.
    if len(out) == before:
      break
  if len(out) != len(order):
    left = [n for n in order if n not in seen]
    print('UNORDERABLE (cycle or missing): %s' % left)
    for n in left:
      print('  %s waits on %s' % (n, sorted(deps[n] - seen)))
    return 1

  # rebuild
  newlines = list(pre)
  for nm in out:
    c, e, head, chunk = defs[nm]
    newlines += chunk + ['']
  # drop trailing blanks, keep one
  while newlines and newlines[-1] == '':
    newlines.pop()
  new = '\n'.join(newlines) + '\n'
  if new == src:
    print('clean after (already ordered, %d defs)' % len(out))
    return 0
  open(path, 'w').write(new)
  print('reordered %d defs; %d moved' % (len(out), sum(1 for a, b in zip(order, out) if a != b)))
  return 0


if __name__ == '__main__':
  sys.exit(main(sys.argv[1]))