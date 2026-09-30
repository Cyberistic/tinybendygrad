#!/usr/bin/env python3
"""Hoist defs until Bend stops complaining about call order.

Bend 2.0.34 requires a def to be declared ABOVE every caller.  The error says
`observed : NAME` for the def that is used too early and points at the caller,
so each round moves NAME's whole definition to just above that caller.  Repeats
until either the file checks or a round makes no progress, which means the error
is something else and should be read rather than shuffled.
"""
import re, subprocess, sys

def def_span(L, name):
    """(start, end) of `def name(...)` including its body and trailing blanks."""
    # match the WHOLE dotted name, so `perms` is not confused with `perms.of`
    pat = re.compile(r'^def ([A-Za-z_][A-Za-z0-9_.]*)[(<]')
    hits = [i for i, l in enumerate(L)
            if (m := pat.match(l)) and m.group(1) == name]
    if len(hits) != 1:
        return None
    i = hits[0]
    j = i + 1
    while j < len(L) and (L[j].startswith((' ', '\t')) or L[j].strip() == ''):
        j += 1
    while j > i and L[j - 1].strip() == '':
        j -= 1
    return (i, j)

def caller_line(out):
    # the header is either `Location:` alone or `Location: <name>`, then the
    # source excerpt with the offending line marked by a `>` after its number
    m = re.search(r'Location:[^\n]*\n.*?\n\s*(\d+)>\|', out, re.S)
    return int(m.group(1)) if m else None

def observed(out):
    m = re.search(r'observed : (\S+)', out)
    return m.group(1).strip("'") if m else None

def holder(out):
    """The def named on the `Location:` line -- whose parameter is at fault."""
    m = re.search(r'Location: ([A-Za-z_][A-Za-z0-9_.]*)\s*\n', out)
    return m.group(1) if m else None

def mark_shared(L, fname, pname):
    """Prefix `pname` with `+` in `def fname(...)`. Bend's share annotation."""
    m = re.search(r'^(def %s\((.*?)\))' % re.escape(fname), '\n'.join(L), re.M)
    if not m:
        return False
    sig = m.group(2)
    if re.search(r'(^|, )\+%s\b' % re.escape(pname), sig):
        return False
    new = re.sub(r'(^|, )%s\b' % re.escape(pname), r'\1+%s' % pname, sig, count=1)
    if new == sig:
        return False
    L[m.start(2):m.end(2)] = [new]
    return True

def check(path, bend):
    r = subprocess.run([bend, path, '--check-only'], capture_output=True, text=True)
    return r.stdout + r.stderr

def main():
    path, bend = sys.argv[1], sys.argv[2]
    seen = set()
    for rnd in range(1, 61):
        L = open(path).read().split('\n')
        out = check(path, bend)
        if 'ALL PROOFS CHECK' in out:
            print('clean after %d hoist(s)' % (rnd - 1))
            return 0
        name, at = observed(out), caller_line(out)
        if False:
            fn, pn = holder(out), name
            if fn and pn and mark_shared(L, fn, pn):
                open(path, 'w').write('\n'.join(L))
                print('round %d: marked +%s shared in %s' % (rnd, pn, fn))
                continue
            print('cannot share %r in %r' % (pn, fn))
            return 1
        if not name or not at:
            print('unhandled error:\n' + out[:600])
            return 1
        span = def_span(L, name)
        if not span:
            print('cannot locate def %s' % name)
            return 1
        s, e = span
        block = L[s:e]
        rest = L[:s] + L[e:]
        at = at - 1
        if at > s:
            at -= 1
        # the call SITE may be deep inside the caller's body, so walk up to the
        # caller's own `def` -- landing mid-body would nest a def in a body
        while at > 0 and not re.match(r'^(def|type|law) ', rest[at]):
            at -= 1
        while at > 0 and rest[at - 1].strip() == '':
            at -= 1
        key = (name, at)
        if key in seen:
            print('no progress on %s at line %d' % (name, at + 1))
            return 1
        seen.add(key)
        rest[at:at] = block + ['']
        open(path, 'w').write('\n'.join(rest))
        print('round %d: hoisted %s above line %d' % (rnd, name, at + 1))
    print('did not converge')
    return 1

sys.exit(main())
