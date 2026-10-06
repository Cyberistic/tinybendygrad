#!/usr/bin/env python3
"""The port's marker census BY DISCOVERY, plus the STALE class.

    .venv/bin/python .agents/slop/portmarkers/markers.py [root]

A marker is a whole-line `#` comment carrying a declared kind: TODO(p1|p3|p4|p6),
FIXME, NOT PORTED, UNPORTED, BACKLOG. bend declares a SIXTH kind the files do not
write down: a `law` with no `def` is an open claim, and `references/bend/bend2/
bend.ts:3847` counts each as a TODO (`book.hols`). That kind is reported here
over the PROOF.bend import CLOSURE, which is where the compiler counts it.

CLASSIFICATION is `checks/marker-audit.py`'s, reproduced so the numbers
reconcile: an entry is the marker's line plus its own following comment lines;
REASONED when that entry matches the WALL vocabulary, or when the def the marker
names is written down in a non-marker comment ELSEWHERE in the same file
(`shared_reason`). Otherwise REACHABLE.

STALE sits on top: a REACHABLE marker whose NAMED def is grepped for as
`def <name>` in the port, `file:line` printed where it exists. A marker that
says "not ported" about a def that IS ported is a claim the tree refutes.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path('tinybendygrad')

KIND = [
    ('TODO(p3)', re.compile(r'^\s*#\s*TODO\(p3\)')),
    ('TODO(pN>3)', re.compile(r'^\s*#\s*TODO\(p[146]\)')),
    ('FIXME', re.compile(r'^\s*#\s*FIXME\b')),
    ('NOT PORTED', re.compile(r'^\s*#\s*NOT PORTED\b')),
    ('UNPORTED', re.compile(r'^\s*#\s*UNPORTED\b')),
    ('BACKLOG', re.compile(r'^\s*#\s*BACKLOG\b')),
]
TODO = re.compile(r'^\s*#\s*TODO\(p\d\)')

WALL = re.compile(
    r'refused:unported|not ported|NOT PORTED|unported|'
    r'\bwall\b|\bdeferred\b|\bblocked\b|\bBLOCKED\b|'
    r'\bdepends on\b|\bneeds (?:a|an|the|`|it)\b|'
    r'\bis (?:P\d|not ported|NOT)\b|\bno (?:Bend|port|substrate)\b|'
    r'\bcannot\b|\bunexpressible\b|--\s*\S|--\s*$', re.I)

DEFN = re.compile(r'^\s*def\s+([A-Za-z_][\w.]*)', re.M)
LAW = re.compile(r'^\s*law\s+([A-Za-z_][\w.]*)', re.M)


def port_defs(root, paths=None):
    names = {}
    for p in (paths if paths is not None else sorted(root.rglob('*.bend'))):
        s = p.read_text(errors='replace')
        for m in DEFN.finditer(s):
            n = m.group(1).split('.')[-1]
            names.setdefault(n, f'{p}:{s[:m.start()].count(chr(10)) + 1}')
    return names


def closure(entry):
    seen, stack = set(), [entry.resolve()]
    while stack:
        p = stack.pop()
        if p in seen or not p.exists():
            continue
        seen.add(p)
        for m in re.finditer(r'^\s*import\s+\./([^\s"#]+)', p.read_text(errors='replace'), re.M):
            if m.group(1).endswith('.bend'):
                stack.append((p.parent / m.group(1)).resolve())
    return seen


def entries(lines):
    for i, l in enumerate(lines):
        if 'TODO(p3)' in l:
            body = [l]
            for nxt in lines[i + 1:]:
                if not nxt.strip().startswith('#') or TODO.match(nxt):
                    break
                body.append(nxt)
            yield i, '\n'.join(body)


def shared_reason(text_lines, name):
    base = name.split('.')[-1]
    if not base or base.startswith('__'):
        return None
    for l in text_lines:
        s = l.strip()
        if not s.startswith('#') or 'TODO(p3)' in s:
            continue
        if re.search(r'`\b' + re.escape(base) + r'\b', s):
            return s.lstrip('# ').strip()[:70]
    return None


def names_of(line):
    return re.findall(r'`([^`]+)`', line) + re.findall(r'\bdef\s+([A-Za-z_][\w.]*)', line)


def main():
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT
    files = sorted(root.rglob('*.bend'))
    defs = port_defs(root)

    counts = {k: 0 for k, _ in KIND}
    rows = []
    for p in files:
        lines = p.read_text(errors='replace').split('\n')
        for i, l in enumerate(lines):
            kind = next((k for k, rx in KIND if rx.match(l)), None)
            if kind is None:
                continue
            counts[kind] += 1
            if kind != 'TODO(p3)':
                continue
            e = next(t for _, t in entries(lines) if t.split('\n')[0] == l)
            named = [n for n in names_of(l) if n.split('.')[-1] in defs]
            if WALL.search(e):
                cls = 'REASONED'
            else:
                nm = named[0].split('.')[-1] if named else ''
                if nm and shared_reason(lines, nm):
                    cls = 'REASONED(shared)'
                elif named:
                    cls = 'STALE'
                else:
                    cls = 'REACHABLE'
            rows.append((str(p), i + 1, e.split('\n')[0].strip(), cls,
                         named[0] if named else ''))

    # bend's own TODO: a `law` with no `def` in its own closure.
    cl = sorted(closure(root / 'PROOF.bend'))
    cdefs = port_defs(root, cl)
    open_claims = []
    for p in cl:
        s = p.read_text(errors='replace')
        for m in LAW.finditer(s):
            n = m.group(1)
            if n.split('.')[-1] not in cdefs:
                open_claims.append((str(p), s[:m.start()].count('\n') + 1, n))

    print(f"# files walked: {len(files)}")
    print(f"# markers found: {sum(counts.values())}")
    for k, _ in KIND:
        print(f"   {k:12} {counts[k]}")
    print(f"   {'OPEN CLAIM':12} {len(open_claims)}   (bend's own TODO, PROOF closure)")
    print()
    per = {}
    for r in rows:
        per[r[3]] = per.get(r[3], 0) + 1
    print(f"# classification of the {counts['TODO(p3)']} TODO(p3) markers: {per}")
    print()
    print("## STALE -- the marker names a def that now EXISTS")
    stale = [r for r in rows if r[3] == 'STALE']
    for p, ln, txt, cls, named in stale:
        print(f"  {p}:{ln}  names `{named}` -> {defs.get(named.split('.')[-1])}")
        print(f"     {txt[:110]}")
    print(f"  ({len(stale)} stale)")
    print()
    print("## OPEN CLAIMS -- laws the PROOF closure declares with no def")
    for p, ln, n in open_claims:
        print(f"  {p}:{ln}  {n}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
