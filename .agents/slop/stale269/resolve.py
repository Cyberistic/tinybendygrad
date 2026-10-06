#!/usr/bin/env python3
"""`NO-FILE` AND `WRONG-FILE`, RESOLVED BY CONTENT. The gate's verdict is about a PATH; this asks
whether the TEXT exists, which is the question a reader of the comment is asking.

    .venv/bin/python .agents/slop/stale269/resolve.py rows.tsv CLASS

For every row it searches EVERY `.py` in the tree, and prints, per candidate file, the line
carrying the quoted text -- so the restore is chosen against a PASTED LINE and not a distance.

**FOUR ANSWERS, AND EACH IS PROVEN, NOT ASSUMED** (the brief's list, in this order):

1. **IT MOVED** -- the text is in the tree at some path; the citation named a different one.
   Proven by: the line that carries the text is pasted.
2. **IT WAS NEVER COMMITTED** -- proven with `git log --all -- <path>` across ALL REFS, not one
   commit and not one path. **This is the `canon.py` lesson: a verdict scoped to one commit
   reads "0" as "never existed".**
3. **IT WAS DELETED** -- and the delete commit names it. `git log --all --diff-filter=D`.
4. **THE CITATION WAS ALWAYS FALSE** -- and restoring would require INVENTING something, so it is
   DECLINED and named.

A path the gate calls missing is frequently a path the gate's own `resolve()` cannot express:
`isa/__init__.py` resolves only as `tinygrad/renderer/isa/__init__.py`, `dtype.py` is ambiguous
under `tinygrad/**`, and `autogen/io_uring.py` lives at `tinygrad/runtime/autogen/io_uring.py`
while `PYROOTS` offers no `tinygrad/runtime/...`. **Those are RESOLVER limits, and they are
different from broken citations** -- `resolve()` returning `None` is not evidence of absence.
"""
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
TREES = ("tinygrad", "examples", "extra", "test", "gates", "checks", "tools")


def all_py() -> list[str]:
    out = []
    for t in TREES:
        for dp, dn, fn in os.walk(os.path.join(ROOT, t)):
            dn[:] = [d for d in dn if d != "__pycache__"]
            out += [os.path.relpath(os.path.join(dp, f), ROOT) for f in fn if f.endswith(".py")]
    return sorted(out)


def ever_committed(path: str) -> list[str]:
    """ALL REFS. `--all` and the pathspec unanchored, because the lesson is that a scoped
    question returns 0 and 0 was read as 'never existed'."""
    r = subprocess.run(["git", "log", "--all", "--format=%h", "--", f"*{path}"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if c]


def deleted(path: str) -> list[str]:
    r = subprocess.run(["git", "log", "--all", "--diff-filter=D", "--format=%h", "--", f"*{path}"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if c]


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want = argv[2]
    paths = all_py()
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want:
            continue
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1].strip()
        print(f"\n===== {port}:{pl}  {cls}  {name}:{cl}  quote `{quote}`")
        print(f"  CLAIM  {src[:170]}")
        base = os.path.basename(name)
        # EVERY `.py` in the tree, not just the ones sharing the basename: `WRONG-FILE` means the
        # gate already found the text in a file with a DIFFERENT name, and a basename filter
        # would hide the very answer the class is about.
        hits = []
        for p in paths:
            body = open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
            ls = sorted({body[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(quote), body)})
            if ls:
                hits.append((p, ls, body.splitlines()))
        if not hits:
            print(f"  ANSWER 4  NEVER COMMITTED AS TEXT ANYWHERE IN THE TREE")
            print(f"    git log --all -- *{name}  -> {ever_committed(name)[:8] or 'NOTHING, ON ANY REF'}")
            print(f"    git log --all --diff-filter=D -- *{name}  -> {deleted(name)[:8] or 'never deleted'}")
            continue
        for p, ls, bl in hits[:6]:
            for n in ls[:4]:
                print(f"  FOUND  {p}:{n}  {bl[n - 1].strip()[:160]}")
        if other:
            print(f"  gate said the text is in: {other}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))