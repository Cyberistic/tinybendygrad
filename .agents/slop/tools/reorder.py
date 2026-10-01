"""Reorder a .bend file so every def/type is declared before its first use.

Comment lines and `type` blocks are carried with the def they document, so the
file's narration survives. Blocks that no def depends on keep their relative
order at the front, which keeps the header where it is.
"""
import re, sys

path = sys.argv[1]
lines = open(path).read().split('\n')

# 1. cut the file into (lead, kind, name, body) units. A unit is a `def`, a
#    `type`, or a run of comments/blank lines. A comment run immediately above a
#    def/type belongs to it.
units = []          # list of dicts
pending = []        # comment/blank lines not yet attached
i = 0
while i < len(lines):
    l = lines[i]
    m = re.match(r'^(def|type) ([A-Za-z0-9_.]+)', l)
    if m:
        body = [l]
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if re.match(r'^(def|type) [A-Za-z0-9_.]+', nxt):
                break
            if nxt.strip() == '' and i + 1 < len(lines) and \
               re.match(r'^(def|type) [A-Za-z0-9_.]+', lines[i + 1]):
                break
            body.append(nxt)
            i += 1
        units.append({'kind': m.group(1), 'name': m.group(2),
                      'lead': pending, 'body': body})
        pending = []
    elif l.strip() == '' or l.lstrip().startswith('#'):
        pending.append(l)
        i += 1
    else:
        units.append({'kind': 'other', 'name': None, 'lead': [l], 'body': []})
        i += 1
if pending:
    units.append({'kind': 'tail', 'name': None, 'lead': pending, 'body': []})

named = {u['name']: u for u in units if u['name']}

def deps(u):
    body = '\n'.join(u['body'])
    out = set()
    for n in named:
        if n == u['name']:
            continue
        # a call: `name(`, not part of a longer dotted name
        if re.search(r'(?<![A-Za-z0-9_.])' + re.escape(n) + r'\s*\(', body):
            out.add(n)
            continue
        # a CONSTRUCTOR USE, which is a use of the type and not a call: a `Data`
        # type's constructor is its own name, and it appears as `Name{` in a record
        # literal or in a `case` pattern. A `type` declaration is not a dependency
        # of its own accessors' callers, so only real uses count.
        if named[n]['kind'] == 'type' and re.search(
                r'(?<![A-Za-z0-9_.])' + re.escape(n) + r'\s*\{', body):
            out.add(n)
    return out

for u in units:
    u['deps'] = deps(u) if u['name'] else set()

order, state = [], {}

def visit(u):
    n = u['name']
    if n is None or state.get(n) == 'done':
        return
    if state.get(n) == 'visiting':
        return                      # a cycle: emit in source order, the checker reports it
    state[n] = 'visiting'
    for d in sorted(u['deps']):
        visit(named[d])
    state[n] = 'done'
    order.append(u)

# `import` and any other unnameable line go out FIRST, in source order: a def may
# only call defs declared above it, and an `import` is a declaration too.
for u in units:
    if u['name'] is None:
        order.append(u)
for u in units:
    if u['name'] and u['name'] not in state:
        visit(u)

# `main` LAST, always: it is the only def the checker treats as an entry point, and a
# file whose `main` is emitted first reads as though the gate were a prelude.
mainu = named.get('main')
if mainu is not None and order and order[-1] is not mainu:
    order = [u for u in order if u is not mainu] + [mainu]

# every named unit must appear exactly once
seen = set()
final = []
for u in order:
    if u['name'] and u['name'] in seen:
        continue
    if u['name']:
        seen.add(u['name'])
    final.append(u)
for u in units:
    if u['name'] and u['name'] not in seen:
        final.append(u)
        seen.add(u['name'])

out = []
for u in final:
    out.extend(u['lead'])
    out.extend(u['body'])
open(path, 'w').write('\n'.join(out))
print(len(named), 'named units,', len(final), 'emitted')
