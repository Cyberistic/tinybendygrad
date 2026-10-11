#!/usr/bin/env python3
"""armsites.py -- census of the tree's OWN index-arming WRITE SITES, by AST.

A population is a regex over the tree's own write sites, not a hand list and
not a basename shape (doctrine 1).  So: walk every committed `.py`/`.sh`/`.md`
under the repo, and record every place that constructs a git command capable of
putting a DELETION or a foreign entry into `.git/index`.

Parsed with `ast` for Python (a regex counted `seen.add(` once as an offender,
106 false positives, in `indextree/REPORT.md` §7).  Shell/Markdown are text,
because there is no shell parser in the stdlib, and that limit is stated rather
than hidden.
"""

import ast
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# The git verbs that can ARM an index.  Each is a capability, named, not a guess.
ARMING = {
    "rm": "--cached makes a deletion while LEAVING the file on disk",
    "add": "stages whatever the index already holds, plus the worktree",
    "reset": "moves HEAD without touching the worktree",
    "checkout": "can rewrite the index from another tree",
    "restore": "writes the index from the worktree or a source",
    "update-index": "writes index entries directly",
    "read-tree": "the DISARM, and it discards staged deletions",
    "stash": "stores and restores the index",
    "apply": "--index / --cached apply against the index",
    "commit": "THE CONSUMER: diffs index vs HEAD",
}

PRUNE = {".git", ".jj", "__pycache__", ".venv", "node_modules", "references", ".ruff_cache"}


def git(*a):
    return subprocess.run(["git", "--no-optional-locks", *a], cwd=ROOT,
                          capture_output=True, text=True, check=False).stdout


def committed() -> set[str]:
    return set(git("ls-tree", "-r", "--name-only", "HEAD").split())


def py_strings(tree: ast.AST) -> list[str]:
    """Every string CONSTANT that is an argv element or a whole argv.

    Docstrings are excluded: they are a Constant that is the whole of an Expr,
    which is exactly what `ast.walk` would otherwise sweep in.
    """
    out = []
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            body = getattr(node, "body", [])
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                docstrings.add(id(body[0].value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
            out.append(node.value)
    return out


def main() -> int:
    tracked = committed()
    files = sorted(p for p in tracked
                   if p.endswith((".py", ".sh", ".bash", ".md", ".zsh")) and not p.startswith(tuple(PRUNE)))
    rows = []
    for rel in files:
        p = ROOT / rel
        try:
            src = p.read_text(errors="replace")
        except OSError:
            continue
        hits = []
        if rel.endswith(".py"):
            try:
                tree = ast.parse(src)
            except SyntaxError:
                continue
            consts = py_strings(tree)
            for verb, why in ARMING.items():
                for c in consts:
                    toks = c.replace(",", " ").split()
                    if verb in toks and any(t.startswith("git") for t in toks) or (
                            verb in toks and toks[0] == verb):
                        hits.append(f"ast:{verb}")
                        break
                    if c.strip() == verb or c.strip() == f"git {verb}":
                        hits.append(f"ast:{verb}")
                        break
        else:
            low = src
            for verb in ARMING:
                if f"git {verb}" in low or f"git -{verb}" in low:
                    hits.append(f"text:{verb}")
        if hits:
            rows.append({"path": rel, "sites": sorted(set(hits))})

    out = Path(__file__).resolve().parent / "armsites.json"
    out.write_text(json.dumps(rows, indent=1))
    print(f"ARMSITES population(committed files walked)={len(files)}  offenders={len(rows)}")
    print(f"ARMSITES wrote {out}")
    byverb = {}
    for r in rows:
        for s in r["sites"]:
            byverb[s] = byverb.get(s, 0) + 1
    for k in sorted(byverb):
        print(f"  {k:18s} {byverb[k]:4d} files   -- {ARMING[k.split(':')[1]]}")
    print()
    for r in rows:
        if any(s.endswith("rm") for s in r["sites"]):
            print(f"  RM-CAPABLE {r['path']}  {r['sites']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
