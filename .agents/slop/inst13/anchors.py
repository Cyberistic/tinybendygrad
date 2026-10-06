#!/usr/bin/env python
"""Does each mutator's SUBJECT still resolve, and do its ANCHORS still match?

Read-only. Extracts the mutation tuples with `ast` (NEVER imports the module:
four of these scripts run their mutation loop at module level and would edit the
LIVE tree on import), then counts each anchor string in the subject.
"""
import ast, os, subprocess, sys, json

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)
TREE = '.agents/slop/inst13/tree/.agents/slop'

# instrument -> (source rel in scratch, list name, anchor index in tuple, subject)
SPEC = {
    'fold-rng-mutate.py':   ('fold-rng-mutate.py',   'MUT',       1, 'tinybendygrad/uop/fold.bend'),
    'ga_mutate.py':         ('ga_mutate.py',         'MUTS',      2, 'tinybendygrad/renderer/amd/generate.bend'),
    'mixin-op-mutate.py':   ('mixin-op-mutate.py',   'MUTATIONS', 1, 'tinybendygrad/mixin/op.bend'),
    'nn-init-mutate.py':    ('nn-init-mutate.py',    'MUT',       1, 'tinybendygrad/nn/__init__.bend'),
    'rf2-mutate.py':        ('rf2-mutate.py',        'MUT',       1, '.agents/slop/rf2root/schedule/rf2_work.bend'),
    'state-mutate.py':      ('state-mutate.py',      'MUT',       1, 'tinybendygrad/nn/state.bend'),
    'tcptx-mutate.py':      ('tcptx-mutate.py',      'MUTATIONS', 1, 'tinybendygrad/renderer/tc_ptx.bend'),
    'tools/mutate-dm.py':   ('tools/mutate-dm.py',   'MUTS',      1, 'tinybendygrad/uop/divandmod.bend'),
    'tools/mutate-sz.py':   ('tools/mutate-sz.py',   'MUTATIONS', 2, 'tinybendygrad/sz.bend'),
}


def anchors_from(src_text, listname):
    tree = ast.parse(src_text)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == listname for t in node.targets):
            out = []
            for elt in node.value.elts:
                out.append(elt)
            return out
    return None


def evaluate(node):
    """Evaluate a literal node with only `chr` in scope (rf2 uses chr(10))."""
    return eval(compile(ast.Expression(node), '<anchor>', 'eval'), {'chr': chr})


results = {}
for name, (rel, listname, idx, subject) in SPEC.items():
    src_path = os.path.join(TREE, rel)
    src = open(src_path, errors='replace').read()
    elts = anchors_from(src, listname)
    if elts is None:
        results[name] = {'error': f'no module-level list {listname}'}
        continue
    anchor_nodes = [e.elts[idx] for e in elts if isinstance(e, ast.Tuple) and len(e.elts) > idx]
    resolved = unique = zero = multi = 0
    zero_labels, multi_labels = [], []
    for i, node in enumerate(anchor_nodes):
        try:
            a = evaluate(node)
        except Exception:                       # noqa: BLE001
            continue
        n = subj = None
        try:
            subj = open(subject, errors='replace').read()
        except OSError:
            subj = None
        n = subj.count(a) if subj is not None else -1
        if n == 1:
            resolved += 1
        elif n == 0:
            zero += 1
            zero_labels.append(a.strip().splitlines()[0][:60])
        else:
            multi += 1
            multi_labels.append(f'{n}x:{a.strip().splitlines()[0][:50]}')
    results[name] = {
        'subject': subject,
        'subject_exists': os.path.exists(subject),
        'n_anchors': len(anchor_nodes),
        'resolved_once': resolved,
        'zero': zero,
        'multi': multi,
        'zero_labels': zero_labels,
        'multi_labels': multi_labels,
    }

for name, r in results.items():
    print(f'\n== {name}')
    if 'error' in r:
        print('   ', r['error']); continue
    print(f"   subject {r['subject']} exists={r['subject_exists']}")
    print(f"   anchors={r['n_anchors']}  resolved_once={r['resolved_once']}"
          f"  ZERO={r['zero']}  MULTI={r['multi']}")
    if r['zero_labels']:
        print('   zero:', r['zero_labels'][:6])
    if r['multi_labels']:
        print('   multi:', r['multi_labels'][:6])

json.dump(results, open('.agents/slop/inst13/anchors.json', 'w'), indent=1)
