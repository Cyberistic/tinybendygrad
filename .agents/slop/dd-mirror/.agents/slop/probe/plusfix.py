#!/usr/bin/env python3
"""Add `+` to the parameter the checker names, until the file checks.

The error is `- expected : r / - observed : r (consumed more than once)` plus a
`Location:` line naming the def and reprinting its signature, so the fix is
mechanical: put `+` in front of that name in that def's `def` line. Stops on any
error that is not the `+` shape, and prints it for a human.
"""
import re, subprocess, sys

PATH = sys.argv[1] if len(sys.argv) > 1 else 'tinybendygrad/engine/jit.bend'
BEND = ['./bin/bend', PATH, '--check-only']

def run():
    r = subprocess.run(BEND, capture_output=True, text=True, timeout=900)
    return r.stdout + r.stderr

for it in range(200):
    out = run()
    if 'ALL PROOFS CHECK' in out:
        print('CHECK OK after %d fixes' % it)
        break
    m = re.search(r'- expected : (\S+)\n- observed : \S+ \(consumed more than once\)', out)
    loc = re.search(r'Location: (\S+)\n\d+ \| (.*)', out)
    if not m or not loc:
        print('STOP at iteration %d -- not a `+` error:\n' % it + '\n'.join(out.splitlines()[:14]))
        break
    name, defname, sigline = m.group(1), loc.group(1), loc.group(2)
    lines = open(PATH).read().split('\n')
    hit = 0
    for i, l in enumerate(lines):
        if l.startswith('def %s(' % defname) or l.startswith('def %s ' % defname):
            if re.search(r'(?<![\w.+])%s(?=\s*[:,)]|,\s)' % re.escape(name), l):
                new = re.sub(r'(?<![\w.+])(%s)(?=\s*[:,)])' % re.escape(name), r'+\1', l, count=1)
                lines[i] = new
                hit = 1
                break
    if not hit:
        print('STOP -- could not patch def %s param %s\n  %s' % (defname, name, sigline))
        break
    open(PATH, 'w').write('\n'.join(lines))
    print('  +%s -> %s' % (name, defname))
else:
    print('STOP -- iteration cap')