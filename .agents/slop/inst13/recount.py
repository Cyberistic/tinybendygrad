#!/usr/bin/env python
"""Re-derive the absent-instrument population BY DISCOVERY (read-only).

Reproduces toolsledger/extract.py's rule A (the generator that names the 16)
without writing its paths.tsv, then classifies the absent INSTRUMENTS BY
CONTENT rather than by the basename regex kind() uses.

Discovery, not trust: nothing here reads INSTRUMENTS.tsv to decide the count.
"""
import re, os, subprocess, csv

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)
text = open('.agents/TOOLS.md', errors='replace').read()
tracked = set(subprocess.run(['git', 'ls-files'], capture_output=True,
                             text=True).stdout.split())


def norm(t):
    t = t.strip().strip('*_[]()`').rstrip('.,;:)("')
    if t.startswith('./'):
        t = t[2:]
    return t


toks = sorted({norm(t) for t in re.findall(r'`([^`\n]+)`', text) if '/' in norm(t)})
toks = [t for t in toks if not (t.startswith(('http', 'git@', '//'))
                                or 'github.com' in t)]
toks = [t for t in toks if re.fullmatch(r'[~A-Za-z0-9_./@+\-]+', t)]


def present(t):
    if t.startswith('/'):
        return os.path.exists(t)
    if t in tracked or os.path.exists(t):
        return True
    return any(f.startswith(t.rstrip('/') + '/') for f in tracked)


INSTR = re.compile(r'(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate)')


def kind(t):
    base = os.path.basename(t)
    if 'oracle' in base or 'arena' in base:
        return 'ORACLE'
    if INSTR.search(base):
        return 'INSTRUMENT'
    return 'EVIDENCE'


rows = [(t, 'PRESENT' if present(t) else 'ABSENT', kind(t)) for t in toks]

from collections import Counter
c = Counter((s, k) for _, s, k in rows)
distinct = len(rows)
pres = sum(v for (s, k), v in c.items() if s == 'PRESENT')
abs_ = sum(v for (s, k), v in c.items() if s == 'ABSENT')
abs_instr = sum(v for (s, k), v in c.items() if s == 'ABSENT' and k == 'INSTRUMENT')
slop_abs = sum(1 for t, s, k in rows if s == 'ABSENT' and t.startswith('.agents/slop/'))

print('== rule A (extract.py), reproduced read-only ==')
print(f'distinct paths : {distinct}')
print(f'present        : {pres}')
print(f'absent         : {abs_}')
print(f'absent INSTRUMENT (kind regex): {abs_instr}')
print(f'absent under .agents/slop/: {slop_abs}')

absent_instr = [(t, s, k) for t, s, k in rows if s == 'ABSENT' and k == 'INSTRUMENT']

# ---- classify BY CONTENT, not by basename ------------------------------------
# A runnable instrument has a runnable extension AND is not a captured stream.
# A captured stream is a .txt/.out/.err/.rows/.tsv data file, or a file whose
# content is a log line (rc=/PASS/CHECK), not code.
CODE_EXT = ('.py', '.mjs', '.js', '.sh', '.bend')

# recoverable blobs, read straight from git (name from INSTRUMENTS.tsv restore)
blob_sha = {}
for r in csv.DictReader(open('.agents/slop/lostinst/INSTRUMENTS.tsv'), delimiter='\t'):
    if r['state'] == 'RECOVERABLE':
        blob_sha[r['path']] = r['restore_or_generator'].split()[3]


def content(rel):
    if rel in blob_sha:
        out = subprocess.run(['git', 'cat-file', 'blob', blob_sha[rel]],
                             capture_output=True)
        return out.stdout
    return None


def content_class(rel):
    ext = os.path.splitext(rel)[1]
    if ext == '':
        return 'REVISION-REF'   # no extension => names a revision/dir, not a file
    data = content(rel)
    if data is None:
        return 'GONE'
    if ext not in CODE_EXT:
        return 'CAPTURED-STREAM'
    runnable = (data[:2] == b'#!' or b'import ' in data[:2000]
                or b'def main' in data or b'\n' in data)
    return 'RUNNABLE-SCRIPT' if runnable else 'UNKNOWN'


print('\n== absent INSTRUMENT rows, classified BY CONTENT ==')
cc = Counter()
for rel, s, k in absent_instr:
    klass = content_class(rel)
    cc[klass] += 1
    print(f'{klass:16} {rel}')
print('\ncontent counts:', dict(cc))

# content instruments = code files that are genuinely an instrument
content_instr = [r for r, s, k in absent_instr if content_class(r) == 'RUNNABLE-SCRIPT']
print(f'\nDEMOMINATOR by content (runnable scripts): {len(content_instr)}')

# cross-check against INSTRUMENTS.tsv's 14
tsv = list(csv.DictReader(open('.agents/slop/lostinst/INSTRUMENTS.tsv'), delimiter='\t'))
print(f'INSTRUMENTS.tsv rows: {len(tsv)}'
      f' (RECOVERABLE={sum(1 for r in tsv if r["state"]=="RECOVERABLE")},'
      f' GONE={sum(1 for r in tsv if r["state"]=="GONE")},'
      f' NOT-A-PATH={sum(1 for r in tsv if r["state"]=="NOT-A-PATH")})')
