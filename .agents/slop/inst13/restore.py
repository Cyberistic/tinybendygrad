#!/usr/bin/env python
"""Restore the 13 absent RUNNABLE instruments into a SCRATCH tree.

Writes only under .agents/slop/inst13/tree/. Never touches the live tree.
"""
import csv, os, subprocess, hashlib

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)
SCRATCH = '.agents/slop/inst13/tree'

CODE_EXT = ('.py', '.mjs', '.js', '.sh', '.bend')
restored = []
for r in csv.DictReader(open('.agents/slop/lostinst/INSTRUMENTS.tsv'), delimiter='\t'):
    rel = r['path']
    if r['state'] != 'RECOVERABLE':
        continue
    if os.path.splitext(rel)[1] not in CODE_EXT:
        continue  # the captured stream is not an instrument
    sha = r['restore_or_generator'].split()[3]
    data = subprocess.run(['git', 'cat-file', 'blob', sha],
                          capture_output=True).stdout
    dst = os.path.join(SCRATCH, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'wb').write(data)
    restored.append((rel, sha, len(data), hashlib.sha256(data).hexdigest()[:12]))

print(f'restored {len(restored)} instruments into {SCRATCH}')
for rel, sha, n, h in restored:
    print(f'  {n:>6}B sha256:{h}  {rel}')
