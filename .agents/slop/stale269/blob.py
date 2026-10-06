#!/usr/bin/env python3
"""WHICH BLOB WAS THE CITATION TAKEN AGAINST. This is the anchor the whole restore rests on.

    .venv/bin/python .agents/slop/stale269/blob.py rows.tsv CLASS [SUBSTR]

A `file:line` number is only defined relative to a blob, so "the line moved" is not a claim about
the CURRENT file, it is a claim about a PAST one. So: find the commit that last wrote the PORT line
carrying the citation, then read the CITED file **at that commit** and ask on which line the quote
sat. That blob is what the author was looking at, and the line it was on is what the number means.

| verdict | meaning | what the restore is |
|---|---|---|
| `WRITTEN-AGAINST` | quote sat on the cited line in the blob the comment was written against | the number was right; the file moved. Restore to the current successor of THAT line. |
| `ALREADY-WRONG`   | it did not, in that blob | the number was wrong at birth. Not a "move". Adjudicate by content. |
| `NO-HISTORY`      | the port line has no history, or the file did not exist then | no anchor; content only. |

`ALREADY-WRONG` IS THE ROW THAT MUST NOT BE HANDLED BY "TAKE THE NEAREST OCCURRENCE". When the
number never named the text, there is no evidence the author meant the nearest one either, and
restoring to it is a guess wearing a proof's clothes.
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


def sh(*a: str) -> str:
    return subprocess.run(a, cwd=ROOT, capture_output=True, text=True).stdout


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_line_history(port: str, line: int) -> list[str]:
    """Commits that touched this exact port line, newest first. `git log -L` follows it."""
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    tally: dict[str, int] = {}
    out = []
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or filt not in port:
            continue
        tgt = G.resolve(name, port, idx)
        rp = os.path.relpath(tgt, ROOT) if tgt else name
        hs = port_line_history(port, int(pl))
        verdict, detail = "NO-HISTORY", ""
        for c in hs:
            b = show(c, rp)
            if b is None:
                detail = f"{c} has no {rp}"
                continue
            lines = sorted({b[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(quote), b)})
            verdict = "WRITTEN-AGAINST" if int(cl) in lines else "ALREADY-WRONG"
            detail = f"{c}: quote at {lines}"
            break
        tally[verdict] = tally.get(verdict, 0) + 1
        out.append((verdict, port, pl, name, cl, near, quote, detail))
    for v, p, l, n, cl, near, q, d in out:
        print(f"{v:16} {p}:{l} -> {n}:{cl} nearest {near}   {d}")
    print("\nTALLY " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))