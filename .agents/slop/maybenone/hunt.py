#!/usr/bin/env python3
r"""Walk the census's OWN population with the census's OWN decision functions, loaded BY PATH,
and look for the ways `_terminates` can answer True while the callee still hands `sys.exit`
a value CPython chose.  Read-only.  Nothing here is a verdict; it is a hole census.
"""
import ast, importlib.util, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "gates"

def load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec); sys.modules[name] = mod
    spec.loader.exec_module(mod); return mod

ec  = load("ec",  HERE / "exitcode-census-gate.py")
pop = load("ecp", HERE / "gates-pop.py")
homes, deriv = pop.gate_homes(ROOT)
files = []
for h in homes:
    for dp, dn, fn in os.walk(ROOT / h, followlinks=False):
        dn[:] = [d for d in dn if d != "__pycache__"]
        files += [Path(dp) / n for n in fn if n.endswith(".py")]

def callee_of(node, env):
    """The same-module function `sys.exit(...)` calls, or None."""
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in env["funcs"]:
        return env["funcs"][node.func.id]
    if isinstance(node, ast.Name) and node.id in env["funcs"]:
        return env["funcs"][node.id]
    return None

def rel(p):
    try: return str(p.relative_to(ROOT))
    except ValueError: return str(p)

def handler_falls_off(fn):
    """try/except arms whose HANDLER BODY does not terminate: the exception path runs off the
    end of `fn`, so `fn` returns None there. `_terminates` never looks at a handler body."""
    out = []
    for node in ast.walk(fn):
        if not isinstance(node, ast.Try):
            continue
        for i, h in enumerate(node.handlers):
            if not ec._terminates(h.body):
                kinds = {ast.ExceptHandler: "except", ast.Try: "else", ast.TryStar: "except*"}.get(type(h), "?")
                out.append((node.lineno, h.lineno, "handler body falls off"))
        if node.orelse and not ec._terminates(node.orelse):
            out.append((node.lineno, node.orelse[0].lineno, "try ELSE clause falls off"))
    return out

def returns_named(fn):
    """{(line, source-of-returned-expression)} for every `return <expr>` in fn."""
    out = []
    stack, seen = list(fn.body), set()
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if id(n) in seen: continue
        seen.add(id(n))
        if isinstance(n, ast.Return) and n.value is not None:
            out.append((n.lineno, ast.unparse(n.value)))
        stack.extend(ast.iter_child_nodes(n))
    return out

print(f"population W = {len(files)} files, homes={homes}")
HOLE = {"A-handler-falls-off": [], "B-delegated-over-none": [],
        "C-callee-returns-str": [], "D-async-main": [], "E-generator-main": [],
        "F-raise-SystemExit-bare": [], "G-name-shadowing": []}

for p in sorted(files):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: continue
    funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    env = {"funcs": funcs, "ints": ec.module_ints(tree), "delegated": ec.own_exits(tree)}

    # F: `raise SystemExit` with no Call -- `extract()` requires `node.exc` to be a Call
    for n in ast.walk(tree):
        if isinstance(n, ast.Raise) and isinstance(n.exc, ast.Name) and n.exc.id == "SystemExit":
            HOLE["F-raise-SystemExit-bare"].append((rel(p), n.lineno))

    # G: a name bound by TWO functions -- `env["funcs"]` keeps the LAST, so a shallower
    # `main` can be read as a nested closure of the same name (or vice versa).
    seen = {}
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            seen.setdefault(n.name, []).append(n.lineno)
    for nm, lines in seen.items():
        if len(lines) > 1 and nm in {s.lineno and None for s in []} | {nm}:
            HOLE["G-name-shadowing"].append((rel(p), nm, lines))

    for lineno, value in ec.extract(tree):
        fn = callee_of(value, env)
        if fn is None: continue
        name = fn.name
        where = f"{rel(p)}:{lineno}"
        # A: the try/except hole -- `_terminates` says True, the handler says otherwise
        for (tline, hline, why) in handler_falls_off(fn):
            if ec._terminates(fn.body) or True:
                HOLE["A-handler-falls-off"].append((where, name, tline, hline, why,
                                                     ec._terminates(fn.body)))
        # B: DELEGATED short-circuits BEFORE returns_none
        if name in env["delegated"] and ec.returns_none(fn):
            HOLE["B-delegated-over-none"].append((where, name, fn.lineno))
        # C: the callee returns a string / bool / collection -> sys.exit prints it, exits 1
        for (rl, src) in returns_named(fn):
            if src.startswith('"') or src.startswith("'") or src.startswith("f\"") or src.startswith("f'"):
                HOLE["C-callee-returns-str"].append((where, name, rl, src[:60]))
        # D/E: async or generator main
        if name in ("main", "run", "entry"):
            if isinstance(fn, ast.AsyncFunctionDef):
                HOLE["D-async-main"].append((where, name))
            if any(isinstance(n, (ast.Yield, ast.YieldFrom)) for n in ast.walk(fn)):
                HOLE["E-generator-main"].append((where, name))

for k, rows in HOLE.items():
    print(f"\n=== {k}: {len(rows)}")
    for r in rows[:40]:
        print("   ", r)
