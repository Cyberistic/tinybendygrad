#!/usr/bin/env python3
"""Census: a module-level DECLARATION of path strings, and a WALK/FILTER over it that DROPS a
member without an `else`.

The shape is not named by hand. It is found by AST over every committed `.py` under three roots:

  A. a DECLARATION -- a module-level `NAME = ( "str", ... )` / `[...]` / `frozenset(...)` whose
     elements are ALL string literals (a path list, or a list containing one), and
  B. a CONSUMER -- a `for x in NAME` or a comprehension `for x in NAME`, inside which some branch
     tests a member's existence (`is_file`/`is_dir`/`exists`/`lexists`) or its type, and

  C. NO ELSE -- that guarded branch has no `else`, and no statement in its body EMITS the member.
     So a member failing the test leaves the population with no row, no count and no name.

`C` is the defect. `A` and `B` are legal on their own.

Every finding names the file, the declaration, the consumer line, and the guard's shape, so the
count can be argued with rather than re-derived.

    usage: .venv/bin/python .agents/slop/droppedinput/census.py [--rows OUT.rows]
"""
from __future__ import annotations

import argparse
import ast
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
ROOTS = ("checks", "gates", ".agents/slop")
PRUNE = (".git", ".jj", "__pycache__", ".venv", "references", "node_modules")

#: the existence/type tests whose `continue`/absence of `else` is a silent drop. A member that
#: fails one of these is not in the population.
GUARD = {"is_file", "is_dir", "exists", "lexists", "is_symlink", "is_relative_to"}

#: calls that put a member INTO a result the caller can see: an append/extend/insert on a list, an
#: assignment collecting it, a yield, a print, a return. A body that calls one of these is NOT a
#: silent drop even without an `else`, because the member is emitted on that branch.
EMIT = {"append", "extend", "insert", "add", "update", "print", "write_text",
        "write_bytes", "yield", "sort", "extend"} | {"yield_"}


def committed_pys() -> dict[pathlib.Path, str]:
    """The population, by DISCOVERY: `os.walk` over three roots, each file marked
    `committed` / `uncommitted` by `git ls-tree` (the COMMIT TREE, never `git ls-files` -- the
    index, which `indextree` measured 88 files invisible to).

    THE POPULATION IS THE WALK, NOT THE TREE. Measured the first time this ran: a committed-only
    population reported 138 files and could not see `.agents/slop/quiesce/snapshot.py`, which is
    not in `HEAD`. A census whose population is a revision cannot see a file being written, and
    every instrument in this tree that is worth anything sees work in progress -- so the walk is
    the population and the revision is a LABEL on each row, which is what it is good for.
    """
    tree = set(subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                              cwd=ROOT, capture_output=True, text=True,
                              check=True).stdout.splitlines())
    out: dict[pathlib.Path, str] = {}
    for r in ROOTS:
        for dirpath, dirnames, filenames in os.walk(ROOT / r):
            dirnames[:] = [d for d in dirnames if d not in PRUNE]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                p = pathlib.Path(dirpath) / fn
                out[p] = "committed" if p.relative_to(ROOT).as_posix() in tree else "uncommitted"
    return out


def string_list(node: ast.AST) -> tuple[str, ...] | None:
    """The string members of a literal tuple/list/set/frozenset at a module-level binding, or
    None if this is not one. `NAME = ("a", "b")` and `NAME = ("a", ROOT / "b")` both qualify --
    the second's second element is a BinOp whose one operand is a path, which is the common
    `(".agents/slop/x.py", ...)` shape written with a constant prefix."""
    vals: list[str] = []
    seq: ast.AST | None = None
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        seq = node
    elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and \
            node.func.id in ("frozenset", "tuple", "list", "sorted") and node.args:
        seq = node.args[0]
    if seq is None:
        return None
    for el in getattr(seq, "elts", []):
        if isinstance(el, ast.Constant) and isinstance(el.value, str):
            vals.append(el.value)
        elif isinstance(el, (ast.BinOp, ast.Call)):
            vals.append("<expr>")  # a path built from a constant prefix; still one member
        else:
            return None  # a non-path member: this is not a path declaration
    return tuple(vals) if vals else None


def declaration_names(tree: ast.Module) -> dict[str, tuple[int, tuple[str, ...]]]:
    """module-level `NAME = <string list>` -> (lineno, members)."""
    out: dict[str, tuple[int, tuple[str, ...]]] = {}
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        names = [t.id for t in targets if isinstance(t, ast.Name)]
        if not names:
            continue
        vals = string_list(node.value)
        if vals:
            for n in names:
                out[n] = (node.lineno, vals)
    return out


def guarded(fn: ast.AST) -> tuple[bool, bool]:
    """(does this body contain an existence/type guard, does it EMIT the member anyway)."""
    has_guard = False
    for n in ast.walk(fn):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in GUARD:
            has_guard = True
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in EMIT:
            return has_guard or True, True
        if isinstance(n, (ast.Yield, ast.YieldFrom)):
            return has_guard, True
    return has_guard, False


def consumers(src: str) -> list[tuple[str, int, str, int]]:
    """every `for X in NAME:` and every comprehension `for X in NAME` -> (name, lineno, shape, lineno-of-guard)."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.For, ast.comprehension)):
            continue
        it = node.iter
        if isinstance(it, ast.Name):
            names = [it.id]
        elif isinstance(it, ast.Tuple):
            names = [e.id for e in it.elts if isinstance(e, ast.Name)]
        else:
            continue
        for n in names:
            for sub in ast.walk(node):
                if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute) and \
                        sub.func.attr in GUARD:
                    out.append((n, getattr(sub, "lineno", 0), type(node).__name__,
                                getattr(sub, "lineno", 0)))
                    break
            else:
                continue
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rows", default=str(pathlib.Path(__file__).with_name("census.rows")))
    a = ap.parse_args()

    rows, findings, no_else = [], 0, 0
    pop = committed_pys()
    n_committed = sum(1 for v in pop.values() if v == "committed")
    for p in sorted(pop):
        src = p.read_text(errors="replace")
        try:
            decls = declaration_names(ast.parse(src))
        except SyntaxError:
            rows.append(f"SKIP    {p.relative_to(ROOT)}  unparseable")
            continue
        if not decls:
            continue
        hits = [(name, ln, shape, gln) for name, ln, shape, gln in consumers(src)
                if name in decls]
        for name, ln, shape, gln in hits:
            dln, members = decls[name]
            node = _guarded_if(src, gln)
            emits = (_chain_ends_in_emit(node, _bound_guards(ast.parse(src)))
                     if node is not None else False)
            findings += 1
            kind = "DROPS-ABSENT" if not emits else "handles-absent"
            no_else += kind == "DROPS-ABSENT"
            rows.append(f"{kind:<22} {pop[p]}  {p.relative_to(ROOT)}:{dln}  {name}"
                        f"({len(members)} member(s))  consumed {shape} at :{ln}, guard at :{gln}"
                        f"  handles-absent={emits}")

    rows.insert(0, f"ROWS population(os.walk .py under {', '.join(ROOTS)}) = {len(pop)}"
                   f"  committed={n_committed} uncommitted={len(pop) - n_committed}")
    rows.insert(1, f"ROWS declaration+consumer sites = {findings}  of which DROPS-ABSENT = {no_else}")
    pathlib.Path(a.rows).write_text("\n".join(rows) + "\n")
    print("\n".join(rows[:2]))
    for r in rows[2:]:
        print("  " + r)
    return 0


def _guarded_if(src: str, guard_line: int) -> ast.If | None:
    """The construct that DECIDES what happens to a member that fails a guard, found from the
    guard call's line.

    Four shapes, and each version of this census knew one fewer than the truth:
      * the guard is IN the test -- `if p.is_file():`            (`inputs()`, pre-fix)
      * the guard is BOUND TO A NAME and the test uses it -- `here = p.is_file() or p.is_dir()`
        then `if not here:`                                       (`--declare`)
      * a TERMINAL `else`                                         (`inputs()`, post-fix)
      * a CONDITIONAL EXPRESSION -- `... if p.is_file() else "ABSENT"`
        (`checks/differ.py:882`, whose `else` is an operand, not a statement)

    Every gap produced a FALSE POSITIVE on the file this unit was fixing, which is `indextree`'s
    183-where-the-truth-is-61 classifier error reproduced inside the census of it.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    bound = _bound_guards(tree)
    is_guard = lambda t: any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)  # noqa: E731
                             and n.func.attr in GUARD for n in ast.walk(t))
    uses_bound = lambda t: any(isinstance(x, ast.Name) and x.id in bound for x in ast.walk(t))  # noqa: E731
    if any(isinstance(n, ast.IfExp) and getattr(n, "lineno", 0) == guard_line and n.orelse
           for n in ast.walk(tree)):
        return next(n for n in ast.walk(tree)
                    if isinstance(n, ast.IfExp) and getattr(n, "lineno", 0) == guard_line and n.orelse)
    best: ast.If | None = None
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        if is_guard(node.test) or uses_bound(node.test):
            if getattr(node, "lineno", 0) <= guard_line <= (node.end_lineno or node.lineno):
                if best is None or node.lineno > best.lineno:
                    best = node
            elif uses_bound(node.test) and getattr(node, "lineno", 0) > guard_line:
                best = best or node  # the binding precedes the `if` that consumes it
    return best


def _bound_guards(tree: ast.Module) -> set[str]:
    """names assigned an expression containing a guard call."""
    return {n.targets[0].id for n in ast.walk(tree)
            if isinstance(n, ast.Assign) and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)
            and any(isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
                    and c.func.attr in GUARD for c in ast.walk(n.value))}


def _inverted_guard(test: ast.AST, bound: set[str] | None = None) -> bool:
    """`not p.is_file()`, or `not here` where `here` was bound to a guard -- the body runs on the
    member that FAILS the guard."""
    node = test.operand if (isinstance(test, ast.UnaryOp) and isinstance(test.op, ast.Not)) else test
    if any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
           and n.func.attr in GUARD for n in ast.walk(node)):
        return True
    return bound is not None and any(isinstance(n, ast.Name) and n.id in bound
                                     for n in ast.walk(node))


def _chain_ends_in_emit(node: ast.If | ast.IfExp, bound: set[str] | None = None) -> bool:
    """True iff the ABSENT case is handled somewhere in this guard.

    Two constructs handle it, and the first version of this census knew only the first -- which is
    how it reported `snapshot.py`'s own `--declare` as a drop site when `if not here:` IS the
    absent branch. A classifier that reports its own fix's file as an offender is the `indextree`
    regex's 183-where-the-truth-is-61 error, reproduced.

      (a) a TERMINAL `else` -- "and if none of the above, THIS"
      (b) an INVERTED test -- `if not p.is_file():` / `if not here:` -- where the BODY is the
          absent case

    This is the whole question. A member that matches no guard leaves the population with no row,
    no count and no name unless one of the two is present.
    """
    if isinstance(node, ast.IfExp):
        return node.orelse is not None
    if _inverted_guard(node.test, bound):
        return True
    cur: ast.stmt = node
    while isinstance(cur, ast.If):
        if not (len(cur.orelse) == 1 and isinstance(cur.orelse[0], ast.If)):
            return cur.orelse != []
        cur = cur.orelse[0]
    return False


if __name__ == "__main__":
    sys.exit(main())