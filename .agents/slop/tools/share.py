"""Add `+` to a def's `Data`/value parameters until `--check-only` is clean.

Bend needs `+` for a parameter read twice in one expression, and the error names
the parameter. This edits the signature, re-checks, and stops when the error moves
off the parameter or the file is clean. It is a DRIVER: it never invents a body.

    python3 .agents/slop/tools/share.py FILE ./bin/bend [--dry]
"""
import re, subprocess, sys, os

path, bend = sys.argv[1], sys.argv[2]
dry = '--dry' in sys.argv

MAX = 400
for it in range(MAX):
    out = subprocess.run([bend, path, '--check-only'], capture_output=True, text=True)
    err = out.stdout + out.stderr
    m = re.search(r'observed : (\w+) \(consumed more than once\)', err)
    if not m:
        m2 = re.search(r'- expected : (\w+)\n- observed : \1 \(consumed more than once\)', err)
        if m2:
            m = m2
    if not m:
        print('clean after %d edit(s)' % it if it else 'clean after')
        print(err.strip().split('\n')[0] if 'FAIL' in err else 'ALL PROOFS CHECK')
        sys.exit(0)
    name = m.group(1)
    src = open(path).read()
    # the def whose PARAMETER LIST mentions `name` right after `def ...(`, and which
    # does NOT already spell `+name`. A `+` that is already there is the fix, so
    # matching it again would produce `++`, which is a parse error.
    pat = re.compile(r'^(def [A-Za-z0-9_.]+\((?:[^()\n]*?))(?<!\+)(\b%s\b)' % re.escape(name), re.M)
    new, n = pat.subn(lambda mm: mm.group(1) + '+' + mm.group(2), src, count=1)
    if n == 0:
        # every candidate already has a `+`, so the error is about a BINDING or a
        # local, not a parameter: report it rather than editing forever.
        print('%r already carries + in every def that takes it; this is a binding' % name)
        print(err.strip()[:800])
        sys.exit(1)
    if dry:
        print('would add + to %s' % name)
        sys.exit(0)
    open(path, 'w').write(new)
    print('+ %s (%d)' % (name, it + 1))
print('gave up after %d edits' % MAX)
sys.exit(1)
