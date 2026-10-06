#!/usr/bin/env python
"""Verify restore commands resolve with non-empty bytes; cross-hash blobs;
search all history for any xd1/mutate.py or basename mutate.py."""
import json, subprocess, hashlib, os
os.chdir(subprocess.run(['git','rev-parse','--show-toplevel'],capture_output=True,text=True).stdout.strip())
recs = json.load(open('.agents/slop/lostinst/census.json'))

print('== verify each RECOVERABLE restore ==')
blobs = {}
for r in recs:
    if r['state'] not in ('RECOVERABLE',):
        continue
    cmd = r['restore'].split()[:4]
    # git cat-file blob SHA
    out = subprocess.run(cmd, capture_output=True)
    ok = out.returncode == 0 and len(out.stdout) > 0
    blobs[r['path']] = hashlib.sha256(out.stdout).hexdigest()
    print(f"{'OK ' if ok else 'BAD'} {len(out.stdout):>7}B  {r['path']}")

print('\n== duplicate blobs among the recoverable ==')
seen = {}
for p, h in blobs.items():
    seen.setdefault(h, []).append(p)
dups = {h: ps for h, ps in seen.items() if len(ps) > 1}
print(dups if dups else 'none — every recovered blob is distinct')

import sys
if '--history' in sys.argv:
    print('\n== search all history for any path ending xd1/mutate.py or basename mutate.py ==')
    names = subprocess.run(['git','log','--all','--pretty=format:','--name-only'],
                           capture_output=True, text=True).stdout.splitlines()
    hits = sorted({n for n in names if n and (n.endswith('xd1/mutate.py') or os.path.basename(n)=='mutate.py')})
    print(hits if hits else 'none in any ref')
