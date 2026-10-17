#!/usr/bin/env python3
r"""Hole A, EXACT: re-implement `_terminates` while RECORDING every `Try` node whose
`bool(handlers) or bool(finalbody)` was the thing that answered True. Those are the tries
`_terminates` never checked the handler body of."""
import ast, importlib.util, os, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]; HERE = ROOT / "gates"
def load(n, p):
    s = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(s)
    sys.modules[n] = m; s.loader.exec_module(m); return m
ec = load("ec", HERE / "exitcode-census-gate.py"); pop = load("ecp", HERE / "gates-pop.py")
homes, _ = pop.gate_homes(ROOT)
files = []
for h in homes:
    for dp, dn, fn in os.walk(ROOT / h, followlinks=False):
        dn[:] = [d for d in dn if d != "__pycache__"]
        files += [Path(dp) / n for n in fn if n.endswith(".py")]
def rel(p):
    try: return str(p.relative_to(ROOT))
    except ValueError: return str(p)

GRADED = []
def T(stmts):
    if not stmts: return False
    last = stmts[-1]
    if isinstance(last, (ast.Return, ast.Raise)): return True
    if isinstance(last, ast.Try):
        GRADED.append(last)
        return T(last.body) and (bool(last.handlers) or bool(last.finalbody))
    if isinstance(last, (ast.With, ast.AsyncWith)): return T(last.body)
    if isinstance(last, ast.If) and last.orelse:
        return T(last.body) and T(last.orelse)
    return False

n = 0
for p in sorted(files):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: continue
    funcs = {f.name: f for f in ast.walk(tree) if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))}
    env = {"funcs": funcs, "ints": ec.module_ints(tree), "delegated": ec.own_exits(tree)}
    for lineno, value in ec.extract(tree):
        fn = None
        if isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id in funcs:
            fn = funcs[value.func.id]
        if fn is None: continue
        GRADED.clear()
        if not T(fn.body): continue          # the census would have called it MAYBE-NONE already
        offs = []
        for t in GRADED:
            for h in t.handlers:
                if not T(h.body): offs.append((t.lineno, h.lineno, "except", h.body))
            if t.orelse and not T(t.orelse): offs.append((t.lineno, t.orelse[0].lineno, "else", t.orelse))
        if not offs: continue
        n += 1
        print(f"{rel(p)}:{lineno}  sys.exit({fn.name}())   fn@{fn.lineno}   returns_none={ec.returns_none(fn)}")
        for tl, hl, kind, body in offs:
            src = " ; ".join(ast.unparse(s).replace(chr(10), " ")[:66] for s in body)
            print(f"      try@{tl} {kind}@{hl} DOES NOT TERMINATE:  {src}")
print(f"\nGRADED-TRY hole-A sites: {n}")
