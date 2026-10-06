#!/usr/bin/env python3
"""CLAUSE II: DOES THE NUMBER MOVE?  Read-only on gates/gatekit.py; that file is NOT edited.

`gates/retention-check.py:174 writer_exits` counts `return`s after the first `self.dir`
ATTRIBUTE REFERENCE. That is a LINE measure. The property `gates/gatekit.py:295` actually claims is
STRUCTURAL: every exit reaches `self._settle(ok)`.

THE INVARIANCE. Delete the `finally:` from `run()` entirely -- break the very construct that makes
the exits safe -- and the line measure does not move. It cannot: it never looked at the `finally`.
**A CLAUSE THAT IS INVARIANT UNDER THE CHANGE IT CLAIMS TO MEASURE IS NOT A CLAUSE.**

THE CORRECTED CLAUSE IS ONE COMPREHENSION: of the exits in `run()`, how many are inside a `try`
whose `finalbody` is non-empty. It moves to 0 when the `finally` goes, because it asks the question
the docstring asks.

AN `id()`-KEYED CONTAINMENT TEST OVER A PYTHON AST IS UNSOUND, and this file's first draft was
one. `ast.Load`, `ast.Store` and `ast.Del` are INTERNED: the same object is the context of every
load in the tree, so "is this node inside that block" answered TRUE for the `return` BELOW the
`finally` purely because `self._settle(ok)` shared its `Load` with it. Measured: 13/13 protected on
a function where 12/13 is the truth. So the descent below carries a DEPTH, not a set of ids.
"""
import ast, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, "gates/gatekit.py")


def run_fn(tree):
    for cls in (n for n in tree.body if isinstance(n, ast.ClassDef)):
        for fn in cls.body:
            if isinstance(fn, ast.FunctionDef) and fn.name == "run":
                return fn
    raise SystemExit("no run()")


def clause_ii_as_shipped(source):
    """EXACTLY `retention-check.writer_exits` for `run`: `return`s after the first `self.dir`."""
    tree = ast.parse(source)
    fn = run_fn(tree)
    writes = [n.lineno for n in ast.walk(fn)
              if isinstance(n, ast.Attribute) and n.attr == "dir"]
    if not writes:
        return None
    rets = sorted(n.lineno for n in ast.walk(fn) if isinstance(n, ast.Return))
    return len(rets), sum(1 for r in rets if r > min(writes))


class Exits(ast.NodeVisitor):
    """`(total, protected)`, by DEPTH: an exit is protected iff it sits inside a `try` that
    actually cleans up on the way out. Depth, not identity -- see the module docstring."""

    def __init__(self) -> None:
        self.total = self.protected = 0
        self.bare: list[int] = []

    def _stmt(self, node, depth: int) -> None:
        for child in ast.iter_child_nodes(node):
            if isinstance(child, ast.Try):
                cleans = depth + 1 if (child.finalbody and any(
                    isinstance(s, (ast.Expr, ast.Assign, ast.AugAssign, ast.Delete))
                    for s in child.finalbody)) else depth
                for s in child.body:
                    self._stmt(s, cleans)
                for h in child.handlers:
                    for s in h.body:
                        self._stmt(s, cleans)
                for s in child.orelse:
                    self._stmt(s, depth)
                for s in child.finalbody:
                    self._stmt(s, 0)
            elif isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda,
                                    ast.ClassDef)):
                continue                      # a nested scope has its own exits
            elif isinstance(child, ast.Return):
                self.total += 1
                if depth:
                    self.protected += 1
                else:
                    self.bare.append(child.lineno)
            else:
                self._stmt(child, depth)

    def run_on(self, fn):
        self._stmt(fn, 0)


def clause_ii_corrected(source):
    tree = ast.parse(source)
    v = Exits()
    v.run_on(run_fn(tree))
    return v.total, v.protected, v.bare


def break_the_finally(source):
    """Rewrite every `try:` that has a `finalbody` into a PLAIN BLOCK, dropping the cleanup.

    The construct is DELETED, not emptied. Emptied would be a different bug and would flatter the
    corrected clause; a bare block is what "no `finally`" means. `ast.unparse` renumbers lines, and
    the shipped clause compares lines only for ORDER, which unparse preserves.
    """
    tree = ast.parse(source)
    fn = run_fn(tree)

    def strip(node):
        """Splice each `try`/`finally` out of its PARENT's statement list, keeping its body.

        Replacing the node in place is not enough: an `ast.Try` with neither `handlers` nor
        `finalbody` is still a `Try`, and `ast.unparse` renders it as a `try:` that cannot compile.
        The construct has to be UNWRAPPED, which is the only faithful reading of "delete the
        `finally`" -- and the body's statements stay, in order, on the same lines.
        """
        for field, value in ast.iter_fields(node):
            if not isinstance(value, list) or not value or not isinstance(value[0], ast.stmt):
                if isinstance(value, list):
                    for v in value:
                        if isinstance(v, ast.AST):
                            strip(v)
                continue
            out = []
            for child in value:
                if isinstance(child, ast.Try) and child.finalbody:
                    for st in child.body:
                        strip(st)
                    out.extend(child.body)
                elif isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    out.append(child)
                else:
                    strip(child)
                    out.append(child)
            setattr(node, field, out)

    strip(fn)
    return ast.unparse(ast.fix_missing_locations(tree))


if __name__ == "__main__":
    source = open(SRC).read()
    print("# CLAUSE II on gates/gatekit.py. READ ONLY -- no edit is made to that file.\n")
    a = clause_ii_as_shipped(source)
    t, p, bare = clause_ii_corrected(source)
    print("  AS SHIPPED  (line measure: `return`s after the first `self.dir` reference)")
    print(f"      total exits {a[0]}   after the write line {a[1]}    -> reports {a[1]}/{a[0]}")
    print("  CORRECTED   (comprehension: exits inside a `try` with a non-empty `finalbody`)")
    print(f"      total exits {t}   protected {p}                -> reports {p}/{t}")

    broken = break_the_finally(source)
    a2 = clause_ii_as_shipped(broken)
    t2, p2, _b2 = clause_ii_corrected(broken)
    print("\n  WITH THE `finally` DELETED FROM `run()`  (an in-memory rewrite; the file is untouched)")
    print(f"      AS SHIPPED  -> {a2[1]}/{a2[0]}")
    print(f"      CORRECTED   -> {p2}/{t2}")

    print("\n# DOES THE NUMBER MOVE?")
    print(f"      line measure : {'MOVES      <-- it is a clause' if a != a2 else 'INVARIANT  <-- it is not a clause'}"
          f"   {a} -> {a2}")
    print(f"      corrected    : {'MOVES      <-- it is a clause' if (t, p) != (t2, p2) else 'INVARIANT  <-- it is not a clause'}"
          f"   {(t, p)} -> {(t2, p2)}")
    print(f"\n# the UNPROTECTED exits in the intact file, by line: {bare}")
    print("#   ONE of them is correct and expected: the `return` BELOW the `finally` runs after the")
    print("#   cleanup by construction, so no clause should demand it be inside the `try`.")
