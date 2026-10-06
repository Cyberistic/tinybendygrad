#!/usr/bin/env python3
"""IS THE CITATION A **RANGE**? `checks/citation-gate.py` matches `name.py:N-M` and adjudicates
only `N` -- so `dtype.py:236-241` whose quote sits on 237 is reported `STALE-LINE` and is not
broken at all.

    .venv/bin/python .agents/slop/stale269/ranges.py rows.tsv CLASS [SUBSTR]

Prints, per row, the ACTUAL citation token as written in the port, its end if it is a range, and
whether the line that now carries the text falls INSIDE it. **A row whose target is inside the
cited range is a FALSE POSITIVE of the instrument, not a broken citation** -- the same shape as
`Allocator` inside `BumpAllocator`, one level up: the pin checks a coordinate when the citation
names a span.
"""
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    nrange = inside = 0
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want or (filt and filt not in port):
            continue
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        m = next((c for c in CITE.finditer(src[int(pl) - 1]) if c.group(1) == name), None)
        if m is None or m.group(3) is None:
            continue
        nrange += 1
        lo, hi = int(m.group(2)), int(m.group(3))
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            continue
        head = open(tgt, encoding="utf-8", errors="replace").read()
        cands = sorted({head[: x.start()].count("\n") + 1
                        for x in re.finditer(re.escape(quote), head)})
        hit = [c for c in cands if lo <= c <= hi]
        if hit:
            inside += 1
            print(f"IN-RANGE  {port}:{pl}  {name}:{lo}-{hi}  text is at {hit} -- NOT BROKEN")
            print(f"  {src[int(pl) - 1].strip()[:165]}")
    print(f"\n  {nrange} of the rows are RANGE citations; {inside} have the text INSIDE the range "
          f"-> instrument false positives", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))