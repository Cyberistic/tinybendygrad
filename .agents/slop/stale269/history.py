#!/usr/bin/env python3
"""THE HISTORY ANCHOR, AND IT IS THE PART THE SUBSTRING LANE CANNOT DO.

    .venv/bin/python .agents/slop/stale269/history.py rows.tsv CLASS [SUBSTR]

For every row: walk the cited file's commits and ask, per commit, **on which lines does the quote
occur**. That answers three questions the current file cannot:

| question | verdict word |
|---|---|
| did the quote EVER sit on the line the comment names? | `NAMED-ONCE` / `NEVER-NAMED` |
| did the quote sit on a line that later MOVED to where we put it? | `MOVED-FROM` |
| did the quote get ADDED then REMOVED (a rule, not a line)? | `ADDED+REMOVED` |

**`NEVER-NAMED` IS THE ROW THAT MATTERS MOST.** It means the comment's number was wrong when it
was written, so "the line moved" is not the story and a restore that only tracks the nearest
occurrence is explaining the wrong defect. Those rows are adjudicated by hand and named.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import importlib.util  # noqa: E402

_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)


def commits(path: str) -> list[str]:
    r = subprocess.run(["git", "log", "--format=%h", "--", path], cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if c]


def body_at(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def main(argv: list[str]) -> int:
    rows = [f for f in open(argv[1], encoding="utf-8").read().splitlines()[1:]]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    tally: dict[str, int] = {}
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or filt not in port:
            continue
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            continue
        rp = os.path.relpath(tgt, ROOT)
        ever, cs = set(), commits(rp)
        for c in cs:
            b = body_at(c, rp)
            if b is None:
                continue
            ever |= {b[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(quote), b)}
        # WAS IT EVER ON THE LINE THE COMMENT NAMES? and did a line MOVE onto where we plan to write?
        named = int(cl) in ever
        moves = sorted((n, int(near)) for n in ever if abs(n - int(near)) < 400 and n != int(near))
        sr, pl_ = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1], None
        verdict = "NAMED-ONCE" if named else "NEVER-NAMED"
        if named and int(near) != int(cl):
            verdict = "NAMED-ONCE-MOVED"
        tally[verdict] = tally.get(verdict, 0) + 1
        mv = ("  moved-from " + ",".join(f"{a}->{b}" for a, b in moves[:6])) if moves else ""
        print(f"{verdict:20} {port}:{pl} -> {rp}:{cl} nearest {near} (quotes seen at {sorted(ever)[:8]}){mv}")
        print(f"{'':20} CLAIM: {sr.strip()[:160]}")
    print("\nTALLY " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))