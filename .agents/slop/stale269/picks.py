#!/usr/bin/env python3
"""THE PICKS FILE IS READ, NOT GUESSED. This prints, for every `AMBIG`/`WEAK` row, the claim and
EVERY candidate with its line pasted, so the pick recorded in `picks.tsv` is checkable.

    .venv/bin/python .agents/slop/stale269/picks.py rows.tsv

One block per row:
    CLAIM   the port lines around the citation
    QUOTE   the text the gate matched
    cand N  <file>:<N>  <the whole line>
The reader chooses N (or none). `apply-picks.py` writes only what is chosen, and REFUSES any pick
whose number is not one of the candidates -- so a pick cannot introduce a line that does not carry
the text.
"""
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
HERE = os.path.join(ROOT, ".agents/slop/stale269")
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def main(argv: list[str]) -> int:
    want = set(argv[2:]) or None
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = G.python_files()
    picked = set()
    pf = os.path.join(HERE, "picks.tsv")
    if os.path.exists(pf):
        picked = {l.split("\t")[0] for l in open(pf).read().splitlines()[1:]}
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        if want and cls not in want:
            continue
        tgt = G.resolve(name, port, idx)
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        m = next((c for c in CITE.finditer(src[int(pl) - 1]) if c.group(1) == name), None)
        if m is not None and m.group(3) is not None and tgt is not None:
            body = open(tgt, encoding="utf-8", errors="replace").read()
            inr = sorted({body[: x.start()].count("\n") + 1 for x in re.finditer(re.escape(quote), body)})
            inr = [n for n in inr if int(m.group(2)) <= n <= int(m.group(3))]
            if inr:
                continue  # already accounted NOT-BROKEN
        if tgt is None or int(occ) == 1 and cls == "STALE-LINE":
            if tgt is None:
                pass
            else:
                continue  # the whole-text rule already owns this one
        rp = os.path.relpath(tgt, ROOT) if tgt else name
        body = open(os.path.join(ROOT, rp), encoding="utf-8", errors="replace").read() if tgt else ""
        cands = sorted({body[: x.start()].count("\n") + 1 for x in re.finditer(re.escape(quote), body)}) if body else []
        if len(cands) < 2:
            continue
        key = f"{port}:{pl}"
        print(f"\n===== {key}  {cls}  {rp}:{cl}  quote `{quote}`  [{'PICKED' if key in picked else ''}]")
        for i in range(max(0, int(pl) - 2), min(len(src), int(pl) + 2)):
            print(f"  CLAIM  {port}:{i+1}  {src[i].strip()[:175]}")
        bl = body.splitlines()
        for n in cands:
            print(f"  cand {n:5d}  {bl[n - 1].strip()[:165]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))