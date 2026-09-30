#!/usr/bin/env python3
# Differential over a list of snippets: /tmp/sz on a one-file tree vs sz.py.
import os, shutil, subprocess, sys

T = '/tmp/snippettree'


def bend(text):
    shutil.rmtree(T, ignore_errors=True)
    os.makedirs(T + '/tinygrad')
    open(T + '/tinygrad/f.py', 'w').write(text)
    r = subprocess.run(['/tmp/sz', T], capture_output=True, text=True, timeout=60)
    lines = [l for l in r.stdout.split('\n') if 'f.py' in l]
    return lines[0].split()[-2:] if lines else ['ERR', r.stdout.strip() or r.stderr.strip()]


def py(text):
    r = subprocess.run(['.venv/bin/python', 'sz.py', T], capture_output=True, text=True, timeout=60)
    lines = [l for l in r.stdout.split('\n') if 'f.py' in l]
    return lines[0].split()[-2:] if lines else ['ERR', r.stderr.strip().split('\n')[-1][:60]]


CASES = [line for line in open(sys.argv[1]).read().split('\n===\n') if line.strip()]
bad = 0
for c in CASES:
  b, p = bend(c), py(c)
  ok = b == p
  bad += not ok
  print(('ok  ' if ok else 'FAIL'), 'bend[%s] py[%s]' % (' '.join(b), ' '.join(p)), '|', repr(c)[:70])
print('%d/%d' % (len(CASES) - bad, len(CASES)))
