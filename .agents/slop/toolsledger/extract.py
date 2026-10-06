#!/usr/bin/env python
"""Authoritative extraction for the TOOLS.md ledger population.

Rule: every backtick-quoted token containing '/', normalized by stripping
markdown emphasis, surrounding parens, trailing punctuation, a leading './',
and excluding URLs. A path is PRESENT iff it exists on disk or appears in
`git ls-files` (or a tracked file lives under it); otherwise ABSENT.

Kind: INSTRUMENT if the basename matches the project's runnable-verdict
vocabulary (gate/check/sweep/differ/e2e/repro/corpus/mutate/selftest/pin/
census), ORACLE if it names an oracle/arena, else EVIDENCE.
"""
import re, os, subprocess, csv, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
os.chdir(ROOT)
text = open('.agents/TOOLS.md').read()
tracked = set(subprocess.run(['git','ls-files'], capture_output=True, text=True).stdout.split())

def norm(t):
    t = t.strip().strip('*_[]()`').rstrip('.,;:)("')
    if t.startswith('./'): t = t[2:]
    return t

toks = sorted({norm(t) for t in re.findall(r'`([^`\n]+)`', text) if '/' in norm(t)})
toks = [t for t in toks if not (t.startswith(('http','git@','//')) or 'github.com' in t)]
toks = [t for t in toks if re.fullmatch(r'[~A-Za-z0-9_./@+\-]+', t)]

def present(t):
    if t.startswith('/'): return os.path.exists(t)
    if t in tracked or os.path.exists(t): return True
    return any(f.startswith(t.rstrip('/') + '/') for f in tracked)

INSTR = re.compile(r'(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate)')
def kind(t):
    base = os.path.basename(t)
    if 'oracle' in base or 'arena' in base: return 'ORACLE'
    if INSTR.search(base): return 'INSTRUMENT'
    return 'EVIDENCE'

rows = [(t, 'PRESENT' if present(t) else 'ABSENT', kind(t)) for t in toks]
with open('.agents/slop/toolsledger/paths.tsv', 'w', newline='') as f:
    w = csv.writer(f, delimiter='\t', lineterminator='\n')
    w.writerow(['path', 'status', 'kind'])
    w.writerows(rows)

from collections import Counter
c = Counter((s, k) for _, s, k in rows)
total = len(rows)
pres = sum(v for (s, k), v in c.items() if s == 'PRESENT')
abs_ = sum(v for (s, k), v in c.items() if s == 'ABSENT')
abs_instr = sum(v for (s, k), v in c.items() if s == 'ABSENT' and k == 'INSTRUMENT')
print(f'distinct paths: {total}')
print(f'present: {pres}')
print(f'absent: {abs_}')
print(f'absent instruments: {abs_instr}')
print(f'absent oracles: {sum(v for (s,k),v in c.items() if s=="ABSENT" and k=="ORACLE")}')
print(f'absent under .agents/slop/: {sum(1 for t,s,k in rows if s=="ABSENT" and t.startswith(".agents/slop/"))}')
print(f'total lines: {len(text.splitlines())}')
lines_naming = sum(1 for l in text.splitlines() if any('/' in norm(t) for t in re.findall(r'`([^`\n]+)`', l)))
print(f'lines naming >=1 path: {lines_naming}')
