#!/usr/bin/env python
"""Cross-check: which RULE produces 333/173, 322/195, 273/136, 506/340,
~213/99 and ~321; and do the 16 ABSENT INSTRUMENTS appear in each?"""
import re, os, subprocess, csv, json
ROOT = subprocess.run(['git','rev-parse','--show-toplevel'],capture_output=True,text=True).stdout.strip()
os.chdir(ROOT)
text = open('.agents/TOOLS.md').read()
tracked = set(subprocess.run(['git','ls-files'],capture_output=True,text=True).stdout.split())
instr = [r['path'] for r in csv.DictReader(open('.agents/slop/toolsledger/paths.tsv'),delimiter='\t')
         if r['status']=='ABSENT' and r['kind']=='INSTRUMENT']
instr_set = set(instr)

EXT = re.compile(r'\.(py|sh|md|bend|mjs|js|txt|tsv|rows|out|err|json|tex|html|rs|c|h|yml|yaml|toml|ini|log)$')

def norm(t):
    t = t.strip().strip('*_[]()`').rstrip('.,;:)("')
    if t.startswith('./'): t = t[2:]
    return t

def present(t):
    if t.startswith('/'): return os.path.exists(t)
    if t in tracked or os.path.exists(t): return True
    return any(f.startswith(t.rstrip('/') + '/') for f in tracked)

def backticks(ext_only):
    out = set()
    for t in re.findall(r'`([^`\n]+)`', text):
        n = norm(t)
        if '/' not in n: continue
        if n.startswith(('http','git@','//')) or 'github.com' in n: continue
        if not re.fullmatch(r'[~A-Za-z0-9_./@+\-]+', n): continue
        if ext_only and not EXT.search(n): continue
        out.add(n)
    return out

def whitespace(ext_only, strip_dots=False):
    out = set()
    for t in re.findall(r'\S+', text):
        n = norm(t)
        if strip_dots: n = n.lstrip('.')
        if '/' not in n: continue
        if n.startswith(('http','git@','//')) or 'github.com' in n: continue
        if not re.fullmatch(r'[~A-Za-z0-9_./@+\-]+', n): continue
        if ext_only and not EXT.search(n): continue
        out.add(n)
    return out

def census(toks):
    absent = [t for t in toks if not present(t)]
    ai = [t for t in absent if t in instr_set]
    return len(toks), len(absent), len(ai), ai

def kind_of(t):
    if 'oracle' in os.path.basename(t) or 'arena' in os.path.basename(t): return 'ORACLE'
    if re.search(r'(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate)', os.path.basename(t)): return 'INSTRUMENT'
    return 'EVIDENCE'

rules = {
  'A backtick, any /':            backticks(False),
  'B backtick, known ext':        backticks(True),
  'C whitespace, known ext':      whitespace(True),
  'C* whitespace, known ext, dots stripped': whitespace(True, True),
  'D whitespace, any /':          whitespace(False),
  'D* whitespace, any /, dots stripped': whitespace(False, True),
}
print(f"{'rule':44} {'distinct':>8} {'absent':>7} {'absentINSTR':>11} {'absentINSTR-of-16':>17}")
for name, toks in rules.items():
    d, a, ai, which = census(toks)
    print(f'{name:44} {d:>8} {a:>7} {ai:>11} {len(set(which)&instr_set):>17}')

# does the instrument set survive under each rule? (are they even tokens there)
print('\nper-instrument membership (1=present in that rule\'s token set):')
rulekeys = list(rules)
print(f"{'path':46} " + ' '.join(f'{chr(65+i)}' for i in range(len(rulekeys))))
for p in instr:
    row = []
    for k in rulekeys:
        row.append('y' if p in rules[k] else '.')
    print(f'{p:46} ' + ' '.join(row))
