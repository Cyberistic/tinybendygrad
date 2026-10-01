#!/usr/bin/env python3
"""toposort-bend.py -- reorder a .bend file's top-level defs so no def uses one
declared below it. Bend has no forward references and the compiler reports ONE
error per run, so fixing them by hand costs a compile cycle each. This does the
whole class at once.

Blocks are the comment run + the `def`/`type` header + the indented body. A
dependency is a bare `name` or `name.` reference to another block's name, where
`name` is not a module prefix this file imports (H, S, O, F, Base, U32, F32,
List, Maybe, String, Char, Bool, Nat, Cmp, IO, Unit, Array, Map, AxisType,
Tuple...). The file's own `type X` block is a dependency for every `X{...}` use.
The original order is the tie-break, so the diff is the minimum movement.
"""
import re, sys

path = sys.argv[1]
src = open(path).read()
lines = src.split('\n')

# ---- split into (kind, name, start, end) blocks, keeping the import header first
blocks = []
i = 0
# the import header
while i < len(lines) and not (lines[i].startswith('def ') or lines[i].startswith('type ')):
    i += 1
header = lines[:i]
while i < len(lines):
    # the trailing trim above leaves `i` on a blank line, so skip the blanks and
    # then gather the comment run that belongs to the next block
    while i < len(lines) and lines[i] == '':
        i += 1
    cstart = i
    # comments AND blanks: a paragraph, a blank, another paragraph and then the
    # def is ONE block, and stopping at the blank silently truncated the parse
    while i < len(lines) and (lines[i].startswith('#') or lines[i] == ''):
        i += 1
    if i >= len(lines) or not (lines[i].startswith('def ') or lines[i].startswith('type ')):
        # not a block start -- put the comments back and stop
        break
    m = re.match(r'^(def|type) ([A-Za-z_][A-Za-z0-9_]*)', lines[i])
    kind, name = m.group(1), m.group(2)
    # the full dotted name, for `def dc_l0.go`
    full = re.match(r'^(?:def|type) ([A-Za-z_][A-Za-z0-9_.]*)', lines[i]).group(1)
    j = i + 1
    while j < len(lines):
        L = lines[j]
        if L == '' or L.startswith('#') or L.startswith(' '):
            j += 1
            continue
        break
    # trim trailing comment/blank lines back to the body
    while j > i + 1 and (lines[j-1] == '' or lines[j-1].startswith('#')):
        j -= 1
    blocks.append({'kind': kind, 'name': name, 'full': full,
                   'start': cstart, 'end': j, 'text': lines[cstart:j]})
    i = j
tail = lines[i:]

if tail and any(l.strip() for l in tail):
    print("WARNING: unparsed tail, first line:", repr(tail[0]))

# ---- import prefixes to ignore
IMPORTS = {'H', 'S', 'O', 'F', 'Base', 'List', 'Maybe', 'String', 'Char',
           'Bool', 'Nat', 'Cmp', 'IO', 'Unit', 'Array', 'Map', 'AxisType',
           'Tuple', 'Some', 'None', 'True', 'False', 'Nil', 'Succ'}

# keyed by the FULL dotted name, so `dc_s_fold` and `dc_s_fold.go` are two
# different nodes. Keying by the bare family name made every sibling an alias
# of the first one and reported a cycle that does not exist.
byfull = {}
for b in blocks:
    byfull.setdefault(b['full'], b)

def deps_of(b):
    out = set()
    # COMMENTS ARE STRIPPED. A def's doc comment names every symbol it talks
    # about -- `gate`, `threefry2x32`, `floordiv_to_idiv` -- and counting those as
    # uses manufactures cycles that do not exist and forces blocks out in the
    # wrong order. Only code is a use.
    body = '\n'.join(L for L in b['text'] if not L.lstrip().startswith('#'))
    for m in re.finditer(r'\b([A-Za-z_][A-Za-z0-9_]*)((?:\.[A-Za-z_][A-Za-z0-9_]*)*)', body):
        base, rest = m.group(1), m.group(2)
        if base in IMPORTS or base in ('case', 'def', 'type', 'match', 'law',
                                       'import', 'do', 'for', 'let', 'in', 'IO'):
            continue
        dotted = (base + rest).rstrip('.')
        for cand in (dotted, base):
            if cand in byfull:
                if byfull[cand] is b:
                    cand = None
                break
        else:
            continue
        if cand is None:
            continue
        out.add(byfull[cand]['full'])
    return out

for b in blocks:
    b['deps'] = deps_of(b)

# ---- Kahn, stable by original index
order = []
avail = [b for b in blocks]
done = set()
while avail:
    progressed = False
    for b in list(avail):
        if b['deps'] <= done:
            order.append(b)
            avail.remove(b)
            done.add(b['full'])
            progressed = True
    if not progressed:
        # A false edge from the name analysis (a `type X` and a `def X.helper`
        # family, or a bare name that happens to share a family). Force the FIRST
        # remaining block out in ORIGINAL order and keep going: the compiler is
        # the real oracle and it names one offender per run, so a near-sort plus a
        # few hand moves beats no sort.
        b = avail[0]
        print("forced (suspect cycle):", b['full'], "<-", ','.join(sorted(b['deps'] - done)))
        order.append(b)
        avail.remove(b)
        done.add(b['full'])

out = list(header)
for b in order:
    out.extend(b['text'])
    out.append('')
out.extend(tail)
open(path, 'w').write('\n'.join(out))
moved = sum(1 for a, b in zip(blocks, order) if a is not b)
print("toposorted %d blocks, %d changed position" % (len(blocks), moved))
