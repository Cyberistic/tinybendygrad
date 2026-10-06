#!/usr/bin/env python3
"""THE RESTORE DECISION, AND IT IS TAKEN AGAINST A BLOB, NOT AGAINST HEAD.

    .venv/bin/python .agents/slop/stale269/decide.py rows.tsv CLASS [SUBSTR]

A `file:line` number is only defined **relative to a blob**, and the blob a citation was written
against is RECOVERABLE: `git log -L<line>:<port>` names the commits that wrote that port line,
and the cited `.py` at any of them is a file the author was demonstrably looking at.

    THE BLOB, THEN THE LINE IN THE BLOB, THEN HEAD.

Head is only consulted to ask "is the historical line still here, and where". Never to ask "which
occurrence is nearest" -- that is the pin that accepted `Allocator` inside `BumpAllocator`.

| verdict | the blob's line set vs the cited number | the restore |
|---|---|---|
| `MOVED`            | cited number IS a line the quote sat on | the CURRENT line carrying that same text |
| `MISNUMBERED`      | the quote sat elsewhere in that blob, uniquely | that line's current successor |
| `MISNUMBERED-AMBIG`| the quote sat on several lines there | NAME IT; content decides, not distance |
| `NO-BLOB`          | no commit, or the file was absent then | NAME IT; content only |

**THE HISTORICAL LINE IS THE ANCHOR AND THE CURRENT LINE IS ONLY ITS ADDRESS.** `MOVED` and
`MISNUMBERED` differ in whether the number was ever right, and that difference decides whether a
restore is a move or a correction -- but BOTH are restored to the same place: the line that says
the thing.

Every row prints the CLAIM, the blob, the historical line, the HEAD line, and -- for anything
ambiguous -- every candidate with its text, so the reader can check the decision instead of
trusting it.
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

VERBOSE = "-q" not in sys.argv


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_history(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def lines_of(body: str, quote: str) -> set[int]:
    return {body[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(quote), body)}


def line_text(body: str, n: int) -> str:
    ls = body.splitlines()
    return ls[n - 1].strip() if 0 < n <= len(ls) else "<PAST EOF>"


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    tally: dict[str, int] = {}
    plan = []
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or filt not in port:
            continue
        tgt = G.resolve(name, port, idx)
        rp = os.path.relpath(tgt, ROOT) if tgt else name
        head = show("HEAD", rp) or ""
        hs = port_history(port, int(pl))
        hist_lines: set[int] = set()
        blob = None
        for c in hs:
            b = show(c, rp)
            if b is None:
                continue
            blob = c
            hist_lines = lines_of(b, quote)
            break
        if blob is None:
            verdict, anchor = "NO-BLOB", None
        elif int(cl) in hist_lines:
            verdict, anchor = "MOVED", int(cl)
        elif len(hist_lines) == 1:
            verdict, anchor = "MISNUMBERED", next(iter(hist_lines))
        else:
            verdict, anchor = "MISNUMBERED-AMBIG", None
        # THE CURRENT ADDRESS of the anchor's text. With `anchor` known it is that occurrence's
        # successor; without one it is every occurrence, and the row must be read.
        cands = sorted(lines_of(head, quote))
        plan.append(dict(cls=cls, port=port, pl=pl, name=name, rp=rp, cl=int(cl), quote=quote,
                         verdict=verdict, anchor=anchor, blob=blob, hsorted=sorted(hist_lines),
                         cands=cands, near=int(near)))
        tally[verdict] = tally.get(verdict, 0) + 1
        if VERBOSE:
            print(f"\n===== {port}:{pl}  {cls}  {name}:{cl} -> nearest {near}")
            print(f"  CLAIM   {open(os.path.join(ROOT, port), encoding='utf-8').read().splitlines()[int(pl)-1].strip()[:170]}")
            print(f"  VERDICT {verdict}  blob {blob}  quote sat at {sorted(hist_lines) or '-'} there; head has {cands}")
            if anchor is not None:
                b = show(blob, rp)
                print(f"  ANCHOR  {rp}@{blob}:{anchor}  {line_text(b, anchor)[:170]}")
                print(f"  HEAD    {rp}:{cands[0] if len(cands) == 1 else cands}")
                if len(cands) == 1:
                    print(f"  LINE    {line_text(head, cands[0])[:170]}")
                else:
                    for c in cands:
                        print(f"    cand  {c}  {line_text(head, c)[:150]}")
    print("\nTALLY " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))