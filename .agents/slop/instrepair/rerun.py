#!/usr/bin/env python
"""After restoring the wiring: does each BROKEN/ORPHANED instrument now RUN and does its
SUBJECT resolve? `bend` is held by another unit, so a bend-compiling mutator is measured by
IMPORT RESOLUTION + ANCHOR RESOLUTION and is NEVER executed (doctrine 2: a SKIP is not a PASS).

Read-only except for capturing subprocess output under .agents/slop/instrepair/run/.
"""
import ast
import json
import os
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)
SLOP = os.path.join(ROOT, ".agents", "slop")
PY = os.path.join(ROOT, ".venv", "bin", "python")
RUN = ".agents/slop/instrepair/run"
os.makedirs(RUN, exist_ok=True)

# instrument -> (anchor-list name, anchor index, subject, claim)
SPEC = {
    "cstyle-shapes-selftest.py": None,
    "substrate-audit.py": None,
    "pin-tables.py": None,
    "ga_mutate.py": ("MUTS", 2, "tinybendygrad/renderer/amd/generate.bend"),
    "nn-init-mutate.py": ("MUT", 1, "tinybendygrad/nn/__init__.bend"),
    "state-mutate.py": ("MUT", 1, "tinybendygrad/nn/state.bend"),
    "tools/mutate-dm.py": ("MUTS", 1, "tinybendygrad/uop/divandmod.bend"),
    "rf2-mutate.py": ("MUT", 1, ".agents/slop/rf2root/schedule/rf2_work.bend"),
    # READ-ONLY controls (needs bend, unchanged by this unit):
    "fold-rng-mutate.py": ("MUT", 1, "tinybendygrad/uop/fold.bend"),
    "mixin-op-mutate.py": ("MUTATIONS", 1, "tinybendygrad/mixin/op.bend"),
    "tcptx-mutate.py": ("MUTATIONS", 1, "tinybendygrad/renderer/tc_ptx.bend"),
    "tools/mutate-sz.py": ("MUTATIONS", 2, "tinybendygrad/sz.bend"),
}
# the ones this unit may EXECUTE (they reach no `bend` call before their own failure)
RUNNABLE = {"cstyle-shapes-selftest.py", "substrate-audit.py", "pin-tables.py", "tools/mutate-dm.py"}


def imports_of(path):
    tree = ast.parse(open(path, errors="replace").read())
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.add(node.module.split(".")[0])
    return names


def resolves(name, here):
    """find_spec locates WITHOUT executing the module."""
    code = (f"import importlib.util,sys;sys.path[:0]=[{here!r},{SLOP!r}];"
            f"print('OK' if importlib.util.find_spec({name!r}) else 'NONE')")
    p = subprocess.run([PY, "-c", code], capture_output=True, text=True)
    return p.returncode == 0 and p.stdout.strip() == "OK"


def anchors(path, listname, idx, subject):
    if listname is None:
        return None
    tree = ast.parse(open(path, errors="replace").read())
    elts = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == listname for t in node.targets):
            elts = node.value.elts
            break
    if elts is None:
        return {"error": f"no module-level list {listname}"}
    try:
        subj = open(subject, errors="replace").read()
    except OSError:
        subj = None
    nodes = [e.elts[idx] for e in elts if isinstance(e, ast.Tuple) and len(e.elts) > idx]
    once = zero = multi = 0
    zerol = []
    for node in nodes:
        try:
            a = eval(compile(ast.Expression(node), "<a>", "eval"), {"chr": chr})
        except Exception:  # noqa: BLE001
            continue
        n = subj.count(a) if subj is not None else -1
        if n == 1:
            once += 1
        elif n == 0:
            zero += 1
            zerol.append(a.strip().splitlines()[0][:64])
        else:
            multi += 1
    return {"n": len(nodes), "once": once, "zero": zero, "multi": multi,
            "subject_exists": subj is not None, "zero_labels": zerol}


def run(path, extra=()):
    here = os.path.dirname(os.path.abspath(path))
    env = dict(os.environ, PYTHONPATH=f"{here}{os.pathsep}{SLOP}")
    p = subprocess.run([PY, path, *extra], capture_output=True, text=True, timeout=300, env=env)
    tag = os.path.basename(path)
    open(f"{RUN}/{tag}.out", "w").write(p.stdout)
    open(f"{RUN}/{tag}.err", "w").write(p.stderr)
    return p.returncode


def used_but_unimported(path):
    """Module-level names referenced but never imported/bound -- catches mutate-dm's `importlib`."""
    src = open(path, errors="replace").read()
    tree = ast.parse(src)
    bound = set(dir(__builtins__)) | {"__name__", "__file__", "__doc__"}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            bound |= {(a.asname or a.name.split(".")[0]) for a in node.names}
        elif isinstance(node, ast.FunctionDef):
            bound.add(node.name)
        elif isinstance(node, (ast.ClassDef,)):
            bound.add(node.name)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
            bound.add(node.id)
        elif isinstance(node, (ast.arg,)):
            bound.add(node.arg)
        elif isinstance(node, ast.ExceptHandler) and node.name:
            bound.add(node.name)
    used = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    return sorted(used - bound - set(__import__("builtins").__dict__))


out = {}
for name, spec in SPEC.items():
    path = os.path.join(SLOP, name)
    row = {"exists": os.path.exists(path)}
    if not row["exists"]:
        out[name] = row
        continue
    missing = [m for m in sorted(imports_of(path)) if not resolves(m, os.path.dirname(path))]
    row["missing_imports"] = missing
    row["unbound"] = [u for u in used_but_unimported(path) if u not in ("sys", "os", "re", "pathlib", "subprocess", "shutil", "tempfile", "json", "ast", "importlib")]
    if name in RUNNABLE:
        row["rc"] = run(path)
    if spec:
        a = anchors(path, *spec)
        row["anchors"] = a
    out[name] = row

json.dump(out, open(".agents/slop/instrepair/rerun.json", "w"), indent=1)
for name, row in out.items():
    print(f"\n== {name}")
    for k, v in row.items():
        if k == "anchors" and isinstance(v, dict):
            print(f"   anchors {v.get('n')} once={v.get('once')} zero={v.get('zero')} multi={v.get('multi')} subj={v.get('subject_exists')}")
        else:
            print(f"   {k}: {v}")
