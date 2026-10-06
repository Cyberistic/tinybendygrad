#!/usr/bin/env python
"""For each absent instrument, find PRESENT code files (.py/.sh/.mjs) that name
it, separating a live reference (invocation/parse) from a comment/prose mention."""
import os, json, re
recs = json.load(open('.agents/slop/lostinst/census.json'))
names = {os.path.basename(r['path']): r['path'] for r in recs}

EXEC = re.compile(r'(subprocess|os\.system|run\(|Popen|exec|check_call|check_output|\$\(|for .* in |python|node|\bbash\b|\bsh\b)')
for base, path in names.items():
    print(f'### {path}')
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('.git','.venv','references','__pycache__')]
        for f in files:
            if not f.endswith(('.py','.sh','.mjs','.js')):
                continue
            p = os.path.join(root, f)
            try:
                lines = open(p, errors='replace').read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                if base in line:
                    kind = 'EXEC' if EXEC.search(line) else 'mention'
                    print(f'  {kind:8} {p}:{i}  {line.strip()[:150]}')
