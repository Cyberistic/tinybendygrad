#!/usr/bin/env python3
"""Mark a Bend parameter `+`-shared until the affine-use errors stop.

Bend 2.0.34 gives every parameter affine ownership unless it is prefixed with
`+`, so a value read twice -- by a comparison and by a recursive call, say --
reports `observed : x (consumed more than once)`. The fix is mechanical, and
doing it by hand across a 300-line port is where mistakes live, so this drives
it from the compiler's own message: `observed` names the parameter and the
`Location:` header names the def that owns it.
"""
import re, subprocess, sys

def run(path, bend):
    r = subprocess.run([bend, path, '--check-only'], capture_output=True, text=True)
    return r.stdout + r.stderr

def mark(L, fname, pname):
    """Prefix `pname` with `+` in `def fname(...)`, by list index. Idempotent."""
    for i, l in enumerate(L):
        m = re.match(r'^def ([A-Za-z_][A-Za-z0-9_.]*)\(', l)
        if not m or m.group(1) != fname:
            continue
        # the signature may wrap onto following lines; gather until the paren
        # balances
        depth = l.count('(') - l.count(')')
        sig = l
        j = i
        while depth > 0 and j + 1 < len(L):
            j += 1
            sig += '\n' + L[j]
            depth += L[j].count('(') - L[j].count(')')
        if re.search(r'(^|[\s,(])\+%s\b' % re.escape(pname), sig):
            return None                      # already shared
        new = re.sub(r'(^|[\s,(])%s\b' % re.escape(pname), r'\1+%s' % pname, sig, count=1)
        if new == sig:
            return None
        L[i:j + 1] = new.split('\n')
        return i + 1
    return None

def main():
    path, bend = sys.argv[1], sys.argv[2]
    for rnd in range(1, 81):
        out = run(path, bend)
        if 'ALL PROOFS CHECK' in out:
            print('clean after %d share(s)' % (rnd - 1))
            return 0
        if 'consumed more than once' not in out:
            print('not a share error:\n' + out[:500])
            return 1
        m = re.search(r'observed : (\S+)', out)
        h = re.search(r'Location: ([A-Za-z_][A-Za-z0-9_.]*)\s*\n', out)
        if not m or not h:
            print('cannot read the error:\n' + out[:500])
            return 1
        pname, fname = m.group(1).strip("'"), h.group(1)
        L = open(path).read().split('\n')
        at = mark(L, fname, pname)
        if at is None:
            print('could not mark +%s in %s' % (pname, fname))
            return 1
        open(path, 'w').write('\n'.join(L))
        print('round %d: +%s in %s (line %d)' % (rnd, pname, fname, at))
    print('did not converge')
    return 1

sys.exit(main())
