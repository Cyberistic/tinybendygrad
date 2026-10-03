#!/usr/bin/env python3
"""Repair the double `#` prefix the first applier introduced.

A comment line that the BEFORE file did NOT have as `# #` but the live file has as
`# #` is a line the applier prefixed twice.  Strip exactly one `#` from it.
Lines that were legitimately `# #` in the BEFORE file are left alone.
"""
import re, sys, os

SNAP = '.agents/slop/commentpass/before/'
files = sys.argv[1:]
DOUBLE = re.compile(r'^(\s*)#\s+#\s?')
total = 0
for p in files:
    sb = SNAP + p
    before = set()
    if os.path.exists(sb):
        for l in open(sb, encoding='utf-8', errors='replace'):
            before.add(l.rstrip('\n'))
    lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    n = 0
    for i, l in enumerate(lines):
        m = DOUBLE.match(l)
        if not m: continue
        if l in before: continue            # was already a double-hash line
        lines[i] = m.group(1) + '#' + l[m.end():]
        n += 1
    if n:
        open(p, 'w', encoding='utf-8').write('\n'.join(lines))
    print(f'{p}: repaired {n} double-hash comment lines')
    total += n
print('total repaired:', total)