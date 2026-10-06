#!/usr/bin/env python
"""Census of the 16 ABSENT INSTRUMENTS named by .agents/TOOLS.md.

Population: .agents/slop/toolsledger/paths.tsv rows with
status==ABSENT and kind==INSTRUMENT (from toolsledger/extract.py).

For each path, decide BY EVIDENCE among:
  RECOVERABLE  bytes exist in git history (commit + blob named)
  GENERATED    reproducible from a named generator (file:line)
  DUPLICATE    byte-equal to a file that EXISTS elsewhere (named)
  GONE         no blob, no generator, no copy

Read-only. Writes only .agents/slop/lostinst/INSTRUMENTS.tsv.
"""
import csv, os, subprocess, hashlib, json

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)

rows = list(csv.DictReader(open('.agents/slop/toolsledger/paths.tsv'), delimiter='\t'))
instruments = [r['path'] for r in rows
               if r['status'] == 'ABSENT' and r['kind'] == 'INSTRUMENT']

def run(*a):
    return subprocess.run(list(a), capture_output=True, text=True)

def blob_in_history(rel):
    """Newest commit C (any ref) whose tree HAS rel, and that blob. None if never."""
    commits = run('git', 'log', '--all', '--format=%H', '--', rel).stdout.split()
    for c in commits:
        rev = run('git', 'rev-parse', f'{c}:{rel}').stdout.strip()
        if not rev:
            continue
        if run('git', 'cat-file', '-t', rev).stdout.strip() == 'blob':
            data = subprocess.run(['git', 'cat-file', 'blob', rev],
                                  capture_output=True).stdout
            return c, rev, data
    return None

def worktree_hashes():
    h = {}
    for dirpath, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('.git', '.venv', 'references')]
        for f in files:
            p = os.path.join(dirpath, f)
            try:
                data = open(p, 'rb').read()
            except OSError:
                continue
            h.setdefault(hashlib.sha256(data).hexdigest(), []).append(p)
    return h

WHASH = worktree_hashes()

def find_generator(rel, blobsha=None):
    """Find .py/.sh/.mjs/.js/.bend source that WRITES this file (by name or blob)."""
    base = os.path.basename(rel)
    out = []
    for dirpath, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('.git', '.venv', 'references')]
        for f in files:
            if not f.endswith(('.py', '.sh', '.mjs', '.js', '.bend')):
                continue
            p = os.path.join(dirpath, f)
            if p == rel:
                continue
            try:
                lines = open(p, 'r', errors='replace').read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                writes = any(k in line for k in ('write_text', 'write(', "open(", '>', '>>', 'Path('))
                if base in line and writes:
                    out.append((p, i, line.strip()[:150]))
    return out

def toks_of_file(rel):
    """Does TOOLS.md name rel, and which kind of row is it on?"""
    hits = []
    for ln, line in enumerate(open('.agents/TOOLS.md', errors='replace'), 1):
        if os.path.basename(rel) in line:
            hits.append((ln, line.strip()[:160]))
    return hits

result = []
for rel in instruments:
    rec = {'path': rel}
    top = os.path.basename(rel)
    bh = blob_in_history(rel)
    if bh:
        c, blob, data = bh
        rec['state'] = 'RECOVERABLE'
        rec['evidence'] = f'blob {blob[:12]} {len(data)}B in commit {c[:12]}'
        rec['restore'] = f'git cat-file blob {blob} > {rel}'
        # duplicate?
        sha = hashlib.sha256(data).hexdigest()
        dups = [p for p in WHASH.get(sha, []) if p != './' + rel.lstrip('./')]
        if dups:
            rec['state'] = 'DUPLICATE'
            rec['evidence'] += f'; byte-equal to {dups[0]}'
            rec['restore'] = f'cp {dups[0]} {rel}'
    else:
        gen = find_generator(rel)
        if gen:
            rec['state'] = 'GENERATED'
            rec['evidence'] = 'generator: ' + '; '.join(f'{p}:{i}' for p, i, _ in gen[:3])
            rec['restore'] = gen[0][0] + ':' + str(gen[0][1])
        else:
            rec['state'] = 'GONE'
            rec['evidence'] = 'no blob in any ref; no generator write site found'
            rec['restore'] = '-'
    rec['tools_lines'] = toks_of_file(rel)
    result.append(rec)

with open('.agents/slop/lostinst/census.json', 'w') as f:
    json.dump(result, f, indent=1)

for r in result:
    print(f"{r['state']:12} {r['path']}")
    print(f"             {r['evidence']}")
    print(f"             restore: {r['restore']}")
