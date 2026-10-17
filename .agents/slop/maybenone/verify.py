#!/usr/bin/env python3
r"""Hole A, narrowed: a `try` whose HANDLER falls off only makes `main` return None when that
`try` is what `_terminates` decided on -- i.e. the LAST statement of the body, or the tail of the
last `with`/`if`. Anything else keeps the later statements.  This prints the tail shape so it can
be read by hand."""
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

def tail_chain(stmts):
    """Follow `if`/`with`/`try` tails down to the statement `_terminates` actually graded."""
    if not stmts: return []
    last = stmts[-1]
    if isinstance(last, ast.Try):
        return [("try", last.lineno)] + tail_chain(last.body)
    if isinstance(last, (ast.With, ast.AsyncWith)):
        return [("with", last.lineno)] + tail_chain(last.body)
    if isinstance(last, ast.If) and last.orelse:
        return [("if", last.lineno)] + tail_chain(last.body)
    return [("stmt", last.lineno)]

def hand_off_try(t):
    """the Try nodes whose handler/orelse falls off, with a flag: is THIS the tail?"""
    out = []
    for n in ast.walk(t):
        if not isinstance(n, ast.Try): continue
        for h in n.handlers:
            if not ec._terminates(h.body): out.append((n, h, "except"))
        if n.orelse and not ec._terminates(n.orelse): out.append((n, n.orelse, "else"))
    return out

n_tail = 0
for p in sorted(files):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: continue
    funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    env = {"funcs": funcs, "ints": ec.module_ints(tree), "delegated": ec.own_exits(tree)}
    for lineno, value in ec.extract(tree):
        fn = None
        if isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id in funcs:
            fn = funcs[value.func.id]
        if fn is None: continue
        chain = tail_chain(fn.body)
        tails = {l for k, l in chain}
        hits = [(t, h, k) for t, h, k in hand_off_try(fn) if t.lineno in tails]
        if not hits: continue
        assert ec._terminates(fn.body) or True
        n_tail += 1
        print(f"{rel(p)}:{lineno}  sys.exit({fn.name}())   fn@{fn.lineno}  tail={'/'.join(k for k,_ in chain)}"
              f"  census says _terminates={ec._terminates(fn.body)}  returns_none={ec.returns_none(fn)}")
        for t, h, k in hits:
            print(f"      try@{t.lineno} {k}@{h.lineno} falls off: "
                  + " | ".join(ast.unparse(s).replace(chr(10), ' ')[:70] for s in h.body))
print(f"\nTAIL-CONFIRMED hole-A sites: {n_tail}")
