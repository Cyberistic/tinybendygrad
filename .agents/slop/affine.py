"""bnxtdev.bend -- FIND AFFINE VIOLATIONS: A NAME READ TWICE WITHOUT `+`.

A parameter is AFFINE unless prefixed `+`, and in Bend 2.0.34 that is checked:
reading one twice is a compile error ("consumed more than once"). A `do`-block
bind WITH `=` follows the same rule (`nm : String = ...` read five times needs
`+nm`). This is the single most common fault in a hand-written port -- on this
file it hit `pbl.encode`, `q.write_off`, `msn.next_of`, `frow`, `db_row`,
`aq_row`, `pbl_row` and a dozen more, one compile cycle each.

    python3 .agents/slop/affine.py tinybendygrad/runtime/support/rdma/bnxtdev.bend

The count is per-body (a def's whole body, not a `match` arm), which is what
Bend checks. Names bound by a `match` pattern or by a `<-` monadic bind are
exempt. ONE KNOWN FALSE POSITIVE: a name read once in each arm of a `match`
counts twice here and needs nothing -- `Tr.has.step.hit`'s `at` is the only one
on this file, and the driver skips it by name.
"""
import re
import sys
from collections import defaultdict

P = sys.argv[1] if len(sys.argv) > 1 else 'tinybendygrad/runtime/support/rdma/bnxtdev.bend'
lines = open(P).read().split('\n')

DEF = re.compile(r'^def\s+([\w.]+)\s*\((.*?)\)\s*->')
SPLIT = re.compile(r',\s*(?![^()]*\))')          # top-level commas only
# a `do`-block bind WITH `=` is affine; one with `<-` is a monadic bind and is not
EQBIND = re.compile(r'^\s*\+?(\w+)\s*:\s*[^=\n]*=')


def bodies():
    starts = [i for i, l in enumerate(lines) if re.match(r'^(def|type) ', l)]
    for k, a in enumerate(starts):
        yield a, (starts[k + 1] if k + 1 < len(starts) else len(lines))


bad = 0
defs = 0
for a, b in bodies():
    m = DEF.match(lines[a])
    if not m:
        continue
    defs += 1
    name = m.group(1)
    plain, where = set(), {}
    for part in SPLIT.split(m.group(2)):
        pm = re.match(r'^(\+?)\s*(\w+)\s*:', part.strip())
        if pm and not pm.group(1):
            plain.add(pm.group(2))
            where[pm.group(2)] = a + 1        # the SIGNATURE line
    body = lines[a + 1:b]
    exempt = set()
    for l in body:
        exempt |= set(re.findall(r'case\s+(\w+)\s*<>', l))          # cons binder
        exempt |= set(re.findall(r'case\s+(\w+)\s*:', l))           # plain binder
        exempt |= set(re.findall(r'case\s+1n\+(\w+)', l))          # countdown binder
    for l in body:
        if not re.match(r'^\s*\+?\w+\s*:.*<-', l):                  # not a monadic bind
            em = EQBIND.match(l)
            if em and not l.lstrip().startswith('+'):
                plain.add(em.group(1))
                where[em.group(1)] = body.index(l) + a + 2   # the BIND line
    used = defaultdict(int)
    for l in body:
        code = l.split('#')[0]
        for tok in re.findall(r'\b([a-z_][a-z_0-9]*)\b', code):
            used[tok] += 1
    for p in sorted(plain):
        if used[p] > 1 and p not in exempt:
            bad += 1
            print(f"line {where.get(p, a + 1)}: {name}: `{p}` read {used[p]}x, "
                  f"needs `+{p}` (bound at line {where.get(p, a + 1)})")
print(f"{P}: {defs} defs, {bad} names read twice without `+` "
      f"(each is a compile error until fixed) -> "
      f"{'none found' if bad == 0 else 'FIX THESE'}")
sys.exit(0)