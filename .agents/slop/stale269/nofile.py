#!/usr/bin/env python3
"""`NO-FILE` IS A VERDICT ABOUT A PATH, AND THE PATH MAY BE THE WRONG QUESTION.

    .venv/bin/python .agents/slop/stale269/nofile.py rows.tsv

For every `NO-FILE` row: does the quoted text exist ANYWHERE in the tree, and at which line?
`checks/citation-gate.py` resolves a name by (a) `PYROOTS/<name>`, (b) the directory MIRROR for a
BARE basename, (c) a unique basename. It does **not** try the mirror for a name that carries a
`/`, so `support/hcq2.py` from `tinybendygrad/runtime/ops_rdma.bend` resolves to nothing even
though the mirror `tinygrad/runtime/support/hcq2.py` is right there. And a bare `dtype.py` is one
of the 15 basenames that are ambiguous under `tinygrad/**`, so it resolves to nothing while the
CLAIM is about a specific one of them.

So each row gets the four answers the brief names, MEASURED:
  `MOVED`      the text is in the tree, at a path, and the citation is off by a prefix
  `AMBIGUOUS`  the text is in the tree, under a basename the gate could not disambiguate
  `ABSENT`     the text is nowhere in the tree or in `gates/` -- proven with `git log --all`
  `PROSE`      the quote is not source text at all (it is itself a citation)
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
TREES = ("tinygrad", "examples", "extra", "gates", "checks", "test")


def every_py() -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for t in TREES:
        for dp, dn, fn in os.walk(os.path.join(ROOT, t)):
            dn[:] = [d for d in dn if d != "__pycache__"]
            for f in fn:
                if f.endswith(".py"):
                    p = os.path.relpath(os.path.join(dp, f), ROOT)
                    out.setdefault(f, []).append(p)
    return out


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = every_py()
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != "NO-FILE":
            continue
        q = quote.strip()
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1].strip()
        hits = []
        for base, paths in sorted(idx.items()):
            for p in paths:
                try:
                    body = open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for m in re.finditer(re.escape(q), body):
                    hits.append((p, body[: m.start()].count("\n") + 1))
        tag = "PROSE" if re.fullmatch(r"[\w./-]+:\d+(-\d+)?", q) else ("ABSENT" if not hits else "FOUND")
        print(f"\n{tag:9} {port}:{pl}  cites {name}:{cl}  quote `{q}`")
        print(f"  CLAIM  {src[:170]}")
        if hits:
            byp: dict[str, list[int]] = {}
            for p, n in hits:
                byp.setdefault(p, []).append(n)
            for p, ns in sorted(byp.items())[:8]:
                print(f"    {p}:{sorted(ns)[:8]}")
        else:
            # THE `git log --all` QUESTION, ACROSS ALL REFS, not one commit and not one path.
            r = subprocess.run(["git", "log", "--all", "--format=%h", "-S" + q, "--", f"*{name}"],
                               cwd=ROOT, capture_output=True, text=True)
            cs = [c for c in r.stdout.split() if c]
            print(f"    git log --all -S`{q}` -- *{name}  ->  {cs or 'NOTHING, ON ANY REF'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))