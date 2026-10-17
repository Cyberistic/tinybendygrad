#!/usr/bin/env python3
r"""Every other way a site can read CHOSEN and still hand CPython the code, walked over the
census's own population, plus the population's own edge.  Read-only."""
import ast, importlib.util, os, sys
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]; HERE = ROOT / "gates"
def load(n, p):
    s = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(s)
    sys.modules[n] = m; s.loader.exec_module(m); return m
ec = load("ec", HERE / "exitcode-census-gate.py"); pop = load("ecp", HERE / "gates-pop.py")
homes, _ = pop.gate_homes(ROOT)
def walk(roots):
    out = []
    for r in roots:
        for dp, dn, fn in os.walk(r, followlinks=False):
            dn[:] = [d for d in dn if d if d not in ("__pycache__", ".git", "node_modules", "references")]
            out += [Path(dp) / n for n in fn if n.endswith(".py")]
    return out
W = walk([ROOT / h for h in homes])
def rel(p):
    try: return str(p.relative_to(ROOT))
    except ValueError: return str(p)

def rets(fn):
    stack, out, seen = list(fn.body), [], set()
    while stack:
        n = stack.pop()
        if id(n) in seen: continue
        seen.add(id(n))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)): continue
        if isinstance(n, ast.Return): out.append((n.lineno, n.value))
        stack.extend(ast.iter_child_nodes(n))
    return out

def is_exit_expr(e):
    if isinstance(e, ast.Call):
        f = e.func
        return (isinstance(f, ast.Attribute) and f.attr == "exit" and isinstance(f.value, ast.Name)
                and f.value.id == "sys") or (isinstance(f, ast.Name) and f.id in ("exit", "quit"))
    return False

H = {k: [] for k in ("B-deLEGATED-over-none", "C-callee-nonint-return", "D-multiarg-exit",
                     "E-aliased-exit", "F-if-without-else-tail", "G-callee-is-async",
                     "H-exit-inside-nested-class")}
kinds = Counter()
for p in sorted(W):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: continue
    funcs = {f.name: f for f in ast.walk(tree) if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))}
    env = {"funcs": funcs, "ints": ec.module_ints(tree), "delegated": ec.own_exits(tree)}
    # D: sys.exit(a, b) -- args[0] is read, the string is still PRINTED
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and is_exit_expr(n) and len(n.args) > 1:
            H["D-multiarg-exit"].append((rel(p), n.lineno, ast.unparse(n)[:70]))
    # E: `from sys import exit as x`
    for n in ast.walk(tree):
        if isinstance(n, ast.ImportFrom) and n.module == "sys":
            for a in n.names:
                if a.name in ("exit", "quit"):
                    H["E-aliased-exit"].append((rel(p), n.lineno, f"from sys import {a.name} as {a.asname or a.name}"))
    for lineno, value in ec.extract(tree):
        fn = None
        if isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id in funcs:
            fn = funcs[value.func.id]
        elif isinstance(value, ast.Name) and value.id in funcs:
            fn = funcs[value.id]
        if fn is None: continue
        w = f"{rel(p)}:{lineno}"
        kinds[ec.classify_site(value, tree, env)[0]] += 1
        if fn.name in env["delegated"] and ec.returns_none(fn):
            H["B-deLEGATED-over-none"].append((w, fn.name, fn.lineno))
        for rl, v in rets(fn):
            if v is None: continue
            src = ast.unparse(v)
            tag = ("STR" if (v.__class__ is ast.Constant and isinstance(v.value, str))
                   else "BOOL" if (v.__class__ is ast.Constant and isinstance(v.value, bool))
                   else "JOINEDSTR" if isinstance(v, ast.JoinedStr)
                   else "LIST" if isinstance(v, (ast.List, ast.Tuple, ast.Dict, ast.Set))
                   else "OTHER")
            if tag in ("STR", "BOOL", "JOINEDSTR", "LIST"):
                H["C-callee-nonint-return"].append((w, fn.name, rl, tag, src[:50]))
        if isinstance(fn, ast.AsyncFunctionDef):
            H["G-callee-is-async"].append((w, fn.name))
        for n in ast.walk(fn):
            if isinstance(n, ast.ClassDef) and any(is_exit_expr(c) for c in ast.walk(n)):
                H["H-exit-inside-nested-class"].append((w, fn.name, n.lineno, n.name))

for k, rows in H.items():
    print(f"{k}: {len(rows)}")
    for r in rows[:20]: print("    ", r)
print(f"\nsame-module callee sites by SHAPE: {dict(kinds)}")

# the population edge: exit sites the census set cannot see
ALL = [p for p in walk([ROOT]) if p not in set(W)]
outside = 0; files_out = set()
for p in sorted(ALL):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: continue
    n = len(ec.extract(tree))
    if n: outside += n; files_out.add(rel(p))
print(f"\nPOPULATION EDGE: W={len(W)} files/{sum(len(ec.extract(ast.parse(p.read_text(errors='replace')))) for p in W if True) if 0 else '-'};"
      f" exit-bearing .py OUTSIDE the homes: {len(files_out)} files, {outside} sites")
for f in sorted(files_out)[:25]: print("    ", f)
