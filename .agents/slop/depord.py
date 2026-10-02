"""bnxtdev.bend -- PUT EVERY DEF IN DEPENDENCY ORDER.

Bend 2.0.34 refuses forward references, and this file had more of them than
compile cycles could afford: `db_row` after `t_db`, `cqe_toggle_at` after
`t_offset_names`, `nth_at` after `frow`, `hdr0_comment_says` before the
constant it reads. The error is reported at the USE, reads like the use's own
block is malformed, and is not -- which is the worst kind of error message.

THE BLOCK RULE, which the first version of this tool got wrong and lost a
`def` line over: a LEADING COMMENT RUN BELONGS TO THE DEF THAT FOLLOWS IT, not
to the def above it. So a block is

    [comment run] + [def/type line] + [body]

and the body ends at the last line before the next block's comment run. Walking
forward and then "moving trailing comments to the next block" is what silently ate
`def t_db()`; pulling the header back over the def line is what does not.

    python3 .agents/slop/depord.py <file>          # report only
    python3 .agents/slop/depord.py <file> --apply  # rewrite (backs up first)

Mutual recursion is refused by Bend anyway, so a legal file always has a
topological order and this never has to guess.
"""
import re
import shutil
import sys
from collections import defaultdict

path = sys.argv[1]
apply_ = '--apply' in sys.argv
lines = open(path).read().split('\n')

DEFHEAD = re.compile(r'^(def|type)\s+([\w.]+)')
DEF = re.compile(r'^def\s+([\w.]+)\s*\((.*?)\)\s*->')
FIELD = re.compile(r'^\s+(\w+)\s*:')


def is_headerish(s):
    """a comment or a blank line: something that can sit above a def"""
    t = s.strip()
    return (not t) or t.startswith('#')


# ---- parse into blocks: [comment run][def line][body] ----------------------
blocks = []          # dict(name, kind, lines, first_line_no)
preamble = []
i = 0
cur = None
while i < len(lines):
    l = lines[i]
    m = DEFHEAD.match(l)
    if m:
        # pull the pending header back over this def
        pend = []
        while cur is not None and is_headerish(cur['lines'][-1]):
            pend.insert(0, cur['lines'].pop())
        cur = {'name': m.group(2), 'kind': m.group(1), 'lines': pend + [l],
               'no': i + 1}
        blocks.append(cur)
        i += 1
        continue
    if cur is None:
        preamble.append(l)
    else:
        cur['lines'].append(l)
    i += 1

# trim trailing blanks from every block and drop empty ones
for b in blocks:
    while b['lines'] and not b['lines'][-1].strip():
        b['lines'].pop()

# ---- what each block defines ------------------------------------------------
def defines(b):
    names = {b['name']}
    hd = next(l for l in b['lines'] if DEFHEAD.match(l))
    m = DEF.match(hd)
    if m:
        for part in re.split(r',\s*(?![^()]*\))', m.group(2)):
            pm = re.match(r'^\+?\s*(\w+)\s*:', part.strip())
            if pm:
                names.add(pm.group(1))
    else:
        for l in b['lines']:
            fm = FIELD.match(l)
            if fm:
                names.add(fm.group(1))
    return names

defined = {b['name']: defines(b) for b in blocks}
by_name = {b['name']: k for k, b in enumerate(blocks)}
if len(by_name) != len(blocks):
    dup = [n for n in by_name if sum(1 for b in blocks if b['name'] == n) > 1]
    print(f"DUPLICATE def names: {dup} -- fix before reordering")
    sys.exit(2)

# ---- dependencies from identifier use --------------------------------------
WORD = re.compile(r'\b([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_0-9]+)*)\b')
deps = defaultdict(set)
for b in blocks:
    own = defined[b['name']]
    code = '\n'.join(l.split('#')[0] for l in b['lines'])
    for tok in WORD.findall(code):
        # The WHOLE dotted token first: Bend names may CONTAIN dots
        # (`mask_nibs.go`, `Tr.has.step`), and splitting on the dot turned
        # `mask_nibs` into a self-dependency and hid a real forward reference.
        # Splitting on the dot is only right for a NAMESPACE access like
        # `DBC_DBC_TYPE_RQ()`, where the head is itself a def.
        if tok in by_name:
            if tok != b['name'] and tok not in own:
                deps[b['name']].add(tok)
            continue
        head = tok.split('.')[0]
        if head in by_name and head != b['name'] and head not in own:
            deps[b['name']].add(head)

viol = []
for nm in defined:
    for d in deps[nm]:
        if by_name[d] > by_name[nm]:
            viol.append((by_name[nm], nm, d))
print(f"{path}: {len(blocks)} blocks, {len(viol)} forward references")
for at, nm, d in sorted(viol):
    print(f"  line {blocks[at]['no']}: `{nm}` uses `{d}`, which is defined LATER")

if not apply_ or not viol:
    sys.exit(1 if viol else 0)

# ---- stable topological rewrite ---------------------------------------------
order, done, temp = [], set(), set()


def visit(nm):
    if nm in done or nm in temp:
        return
    temp.add(nm)
    for d in sorted(deps[nm]):
        if d in by_name:
            visit(d)
    temp.discard(nm)
    done.add(nm)
    order.append(nm)


for b in blocks:
    visit(b['name'])

shutil.copy(path, path + '.depord.bak')
new = '\n'.join(preamble).rstrip('\n') + '\n\n' + '\n'.join(
    '\n'.join(blocks[by_name[nm]]['lines']) for nm in order) + '\n'
open(path, 'w').write(new)
print(f"REWROTE {path} in dependency order ({len(order)} blocks; "
      f"backup at {path}.depord.bak)")