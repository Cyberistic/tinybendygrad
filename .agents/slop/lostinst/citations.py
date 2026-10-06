#!/usr/bin/env python
"""Gather citations for each absent instrument: which document names it, i.e.
what claim its evidence was carrying. Scans AGENTS.md, checks/, gates/,
.agents/TOOLS.md, .agents/TODO.md, and .agents/slop/**/*.md (residue)."""
import os, json

recs = json.load(open('.agents/slop/lostinst/census.json'))

SCAN_DIRS = ['.agents/slop', 'checks', 'gates']
SCAN_FILES = ['AGENTS.md', '.agents/TOOLS.md', '.agents/TODO.md']

def iter_docs():
    for p in SCAN_FILES:
        if os.path.exists(p):
            yield p
    for d in SCAN_DIRS:
        for root, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if x not in ('__pycache__',)]
            for f in files:
                if f.endswith(('.md', '.py', '.sh', '.tsv', '.rows')):
                    yield os.path.join(root, f)

docs = list(dict.fromkeys(iter_docs()))

for r in recs:
    b = os.path.basename(r['path'])
    hits = []
    for p in docs:
        try:
            for i, line in enumerate(open(p, errors='replace'), 1):
                if b in line and p != r['path']:
                    hits.append((p, i, line.strip()[:200]))
        except OSError:
            continue
    r['citations'] = hits
    print(f"##### {r['path']}  [{r['state']}]")
    for p, i, line in hits:
        print(f"  {p}:{i}  {line}")

json.dump(recs, open('.agents/slop/lostinst/census.json', 'w'), indent=1)
