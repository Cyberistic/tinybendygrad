"""Delete the constants that nothing reads.

The leaf sweep measured 60 mutations that move no gate row. Nine of those are
register NAMES shared across two Python lines and three are logic equivalences,
both of which stay. The other 51 are numeric constants, and 46 of those have
ZERO call sites anywhere in the file: no def reads them and no gate row prints
them, so no mutation of them can ever move a row.

A def with no call site is provably behaviour-preserving to delete, so it is
dead weight rather than a port. This script refuses to remove anything that is
not exactly unread -- it counts `NAME(` across the whole file and requires the
count to be 1, which is the definition itself.
"""
import io, re, sys

P = 'tinybendygrad/runtime/support/am/ip.bend'
s = io.open(P, encoding='utf-8').read()
names = sys.argv[1:]
L = s.split('\n')
out, dropped = [], []
for line in L:
  m = re.match(r'^def ([\w.]+)\([^()]*\) -> [^:]+: *-?\d+n?$', line)
  if m and m.group(1) in names:
    n = m.group(1)
    uses = len(re.findall(rf'\b{re.escape(n)}\(\)', s))
    if uses != 1:
      sys.exit(f'REFUSING {n}: {uses} call sites, not 1')
    dropped.append(n)
    continue
  out.append(line)
missing = set(names) - set(dropped)
if missing:
  sys.exit(f'NOT FOUND as one-line literal defs: {sorted(missing)}')
io.open(P, 'w', encoding='utf-8').write('\n'.join(out))
print(f'dropped {len(dropped)} unread constants')