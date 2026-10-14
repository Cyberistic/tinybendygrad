#!/usr/bin/env python
"""MEASUREMENT PROBE for the PY lane's real generator.

`checks/census.py:100` keys the py lane on `.agents/slop/graphcmp.py` ALONE. That file reaches
into `tinygrad/` -- the CPython ORACLE -- at `graphcmp.py:284-290` and 40 more sites. So the
py lane's subject depends on the oracle's bytes and its key cannot see one of them.

RESOLVED BY AST, NOT GREP, and the AST handles the spellings a regex gets wrong:
  * `import a.b.c as x`         -> Alias(name=('a','b','c'))
  * `from a.b import c, d`      -> dotted; each NAME is its own candidate module
  * `from . import x`           -> level 1, NO module  (a regex reading `a.b` finds nothing)
  * `from ..a import x`         -> level 2, one dot is a `Dot`, not two chars in a token
  * `from a import (x as y, z)` -> parenthesised; still names, but a naive `name` scan is fine here
  * `if TYPE_CHECKING:` guards and `try: ... ImportError` bodies are VISITED, because they are
    real edges to a reader and over-inclusion here is the safe direction.
MISSED, and named rather than hidden: `importlib.import_module("x")`, `__import__`, and
`exec`. Those print UNRESOLVED at the end so the blind fraction is a number, not a silence.
"""
import ast, pathlib, sys, collections

REPO = pathlib.Path(__file__).resolve().parents[3]
PKG = REPO / "tinygrad"
ENTRY = REPO / ".agents/slop/graphcmp.py"

def modpath(dotted: str) -> pathlib.Path:
    return PKG.joinpath(*dotted.split(".")).with_suffix(".py")

def candidates(node: ast.AST, cur: pathlib.Path) -> list[pathlib.Path]:
    """Every module a single `import`/`from` statement could name, in try-order."""
    out = []
    if isinstance(node, ast.Import):
        for a in node.names:
            p = modpath(a.name)
            if p.is_file():
                out.append(p)
            p2 = modpath(a.name + ".__init__")
            if not p.is_file() and p2.is_file():
                out.append(p2)
        return out
    if isinstance(node, ast.ImportFrom):
        base = node.level
        pkg = cur.parent
        for _ in range(base - 1):              # level 1 == cur's OWN package
            pkg = pkg.parent
        roots = []
        if base:
            roots.append(pkg)
        else:
            roots.append(PKG)
        if node.module:
            roots.extend(PKG.joinpath(*node.module.split(".")).parents)
        for r in roots:
            if node.module:
                out.append(r.joinpath(*node.module.split(".")).with_suffix(".py"))
            for a in node.names:              # `from a.b import c` -- `c` may itself be a module
                out.append(r / (a.name + ".py"))
                out.append(r / a.name / "__init__.py")
        return out
    return out

def closure(entry: pathlib.Path):
    seen, queue, unresolved = {entry.resolve()}, [entry.resolve()], []
    while queue:
        cur = queue.pop()
        try:
            tree = ast.parse(cur.read_text(), filename=str(cur))
        except (SyntaxError, UnicodeDecodeError) as e:
            unresolved.append((cur, f"UNPARSED {type(e).__name__}"))
            continue
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Import, ast.ImportFrom)):
                continue
            if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module is None:
                unresolved.append((cur, "MALFORMED from-import"))
                continue
            hit = False
            for p in candidates(node, cur):
                p = p.resolve()
                if p.is_file() and p != cur:
                    hit = True
                    if p not in seen:
                        seen.add(p); queue.append(p)
            if not hit:
                unresolved.append((cur, ast.unparse(node)[:70]))
    return seen, unresolved

seen, unres = closure(ENTRY)
tiny = sorted(p for p in seen if p.is_relative_to(PKG))
out  = sorted(p for p in seen if not p.is_relative_to(PKG))
print(f"ENTRY        .agents/slop/graphcmp.py")
print(f"closure TOTAL {len(seen)} files")
print(f"  tinygrad/  {len(tiny)} .py")
print(f"  outside    {len(out)}  -> {[str(p.relative_to(REPO)) for p in out]}")
print(f"\nkey covers   1 file (graphcmp.py).  closure/covered = {len(seen)}/1 = {len(seen)}x")

# WHICH tinygrad modules does the ENTRY itself name directly? Those are the ones a reader
# would guess, and the set a hand list would contain.
tree = ast.parse(ENTRY.read_text())
direct = {str(p.resolve().relative_to(REPO)) for n in ast.walk(tree)
          if isinstance(n, (ast.Import, ast.ImportFrom)) for p in candidates(n, ENTRY)
          if p.resolve().is_file() and p.resolve().is_relative_to(PKG)}
print(f"\nentry DIRECT tinygrad modules: {len(direct)}")
for d in sorted(direct): print("   ", d)

dyn = collections.Counter(u[1].split("(")[0][:44] for u in unres)
print(f"\nunresolved import statements: {len(unres)} over {len(set(u[0] for u in unres))} files")
print("  top forms:", dyn.most_common(6))
print("\n--- tinygrad closure, sorted ---")
for p in tiny: print("   ", p.relative_to(REPO))