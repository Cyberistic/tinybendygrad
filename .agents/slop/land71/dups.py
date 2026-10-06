import subprocess, sys
from collections import defaultdict

def run(args):
    return subprocess.run(args, capture_output=True, text=True).stdout

def tree_map(rev):
    out = run(['git', 'ls-tree', '-r', rev, '--format=%(objectname) %(path)'])
    m = {}
    for line in out.splitlines():
        h, _, p = line.partition('\t') if '\t' in line else (line.split(' ', 1)[0], '', line.split(' ', 1)[1])
        m[p] = h
    return m

a = tree_map('afd395686')
h = tree_map('HEAD')
dirty = set(l.rstrip('\n') for l in open('/tmp/dirty.txt'))
changed = set(open('/tmp/afd_changed.txt').read().split())
inter = sorted(dirty & changed)
inv = defaultdict(list)
for p, b in h.items():
    inv[b].append(p)
for p in inter:
    b = a.get(p)
    dups = [q for q in inv.get(b, []) if q != p]
    # verify blob resolvable + non-empty
    show = subprocess.run(['git', 'show', f'afd395686:{p}'], capture_output=True)
    size = len(show.stdout)
    rc = show.returncode
    print(f'{p}\tblob={b[:10] if b else "ABSENT"}\tresolves_rc={rc}\tbytes={size}\tdups_in_HEAD={dups[:2]}')
