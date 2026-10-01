#!/usr/bin/env python3
"""Append a chunk to a .bend file and check it, reporting def-order and + errors.

    python3 .agents/slop/tools/append.py FILE  (chunk on stdin)

Order rule measured on bend 2.0.34: `def f.b(...)` must be DECLARED BEFORE
`def f.a(...)` that calls it, and a dotted helper must precede the dotted entry
point that calls it. The compiler says "expected: a filled definition" for the
first violation, which names the CALLER and not the called, so it is easy to
misread. This script reports both names.
"""
import subprocess, sys, re

path = sys.argv[1]
chunk = sys.stdin.read()
src = open(path).read()
if not src.endswith('\n'):
  src += '\n'
open(path, 'w').write(src + chunk)

for lane in ('--check-only', None):
  cmd = ['./bin/bend', path] + ([lane] if lane else [])
  r = subprocess.run(cmd, capture_output=True, text=True)
  out = r.stdout + r.stderr
  if 'ALL PROOFS CHECK' in out:
    print(f'OK ({lane or "interpreted"})  {path}  '
          f'{sum(1 for l in open(path) if re.match(r"^(def|type) ", l))} defs, '
          f'{len(open(path).read())} bytes')
    break
  print(out[:900])
  m = re.search(r'observed : (\S+)', out)
  n = re.search(r'Context:\n- (\S+)\s+:', out)
  if m and n:
    print(f'>>> ORDER/REF: {n.group(1)} is used before {m.group(1)} is defined '
          f'(or {m.group(1)} needs a `+`)')
  sys.exit(1)