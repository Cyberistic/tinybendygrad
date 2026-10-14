#!/usr/bin/env python
"""WHY IS A MODULE IN THE CLOSURE? `probe-pyclosure.py` OVER-COUNTS, and an over-count that is
not traced is indistinguishable from a fact. This prints the IMPORT CHAIN and the syntactic
position of every edge on it, so a reader can see which edges a program actually takes at
runtime and which exist only because the AST visits a `try:` body or a `TYPE_CHECKING:` guard.

  [LIVE]  unconditional top-level import
  [TRY]   inside a `try:` -- usually `except ImportError`, so the edge may not fire
  [GUARD] `if TYPE_CHECKING:` -- never fires at runtime
  [FUNC]  inside a function body -- fires only if that function is CALLED
  [IF..]  inside some other conditional
"""
import ast, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
PKG = REPO / "tinygrad"
WANT = sys.argv[1:] or ["tinygrad/VIZ/__init__.py", "tinygrad/viz/serve.py",
                        "test/mockgpu/gpu.py", "tinygrad/nn/state.py"]
WANT = {str((REPO / w).resolve()) for w in WANT}

def position(node, par):
    cls = "LIVE"
    cur = node
    while cur in par:
        p = par[cur]
        if isinstance(p, ast.Try) and cls == "LIVE":
            cls = "TRY"
        elif isinstance(p, ast.If) and cls == "LIVE":
            t = ast.unparse(p.test)
            cls = "GUARD" if "TYPE_CHECKING" in t else f"IF({t[:22]})"
        elif isinstance(p, (ast.FunctionDef, ast.AsyncFunctionDef)) and cls == "LIVE":
            cls = "FUNC"
        cur = p
    return cls

def modpath(d): return PKG.joinpath(*d.split(".")).with_suffix(".py")

def candidates(node, cur):
    out = []
    if isinstance(node, ast.Import):
        for a in node.names: out.append(modpath(a.name))
        return out
    if not isinstance(node, ast.ImportFrom):
        return out
    roots = []
    if node.level:
        pkg = cur.parent
        for _ in range(node.level - 1): pkg = pkg.parent
        roots.append(pkg)
    else:
        roots.append(PKG)
    for r in roots:
        if node.module: out.append(r.joinpath(*node.module.split(".")).with_suffix(".py"))
        for a in node.names:
            out.append(r / (a.name + ".py")); out.append(r / a.name / "__init__.py")
    return out

entry = (REPO / ".agents/slop/graphcmp.py").resolve()
prev = {entry: None}
q = [entry]
while q:
    cur = q.pop(0)
    try: tree = ast.parse(cur.read_text(), filename=str(cur))
    except Exception: continue
    par = {c: n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Import, ast.ImportFrom)): continue
        for p in candidates(node, cur):
            p = p.resolve()
            if p.is_file() and p not in prev:
                prev[p] = (cur, node, position(node, par))
                q.append(p)

for p in sorted(prev):
    if str(p) not in WANT: continue
    print(f"\n### {p.relative_to(REPO)}")
    chain, cur = [], p
    while cur is not None:
        rec = prev[cur]
        if rec is None:
            chain.append(f"  {cur.relative_to(REPO)}  [ENTRY]"); break
        src, node, cls = rec
        chain.append(f"  {cur.relative_to(REPO)}\n      <- {ast.unparse(node)[:60]!r}  [{cls}]")
        cur = src
    print("\n".join(reversed(chain)))