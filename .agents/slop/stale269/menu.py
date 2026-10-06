#!/usr/bin/env python3
"""THE ADJUDICATION MENU. One block per row: the CLAIM, the blob it was written against, the
historical line(s), and EVERY current candidate with its full line. The reader picks; this file
never picks.

    .venv/bin/python .agents/slop/stale269/menu.py rows.tsv CLASS [SUBSTR] > menu.out

It writes ONE TSV, `plan.tsv`, for the rows that are UNAMBIGUOUS -- `occ == 1` at HEAD, or a
single historical anchor whose text is unique now -- and prints the rest for a human. **A row is
only auto-planned when there is exactly one line in the file that can carry the claim, so "the
only place this text appears" is not a guess.** Everything else is a `PICK` and stays unpicked.
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
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_history(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def lset(body: str, q: str) -> list[int]:
    return sorted({body[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(q), body)})


def ltext(body: str, n: int) -> str:
    ls = body.splitlines()
    return ls[n - 1].strip() if 0 < n <= len(ls) else "<PAST-EOF>"


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want = argv[2]
    idx = G.python_files()
    plan, picks = [], []
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want:
            continue
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            picks.append((cls, port, pl, name, cl, quote, "NO-FILE", [], []))
            continue
        rp = os.path.relpath(tgt, ROOT)
        head = show("HEAD", rp) or ""
        cands = lset(head, quote)
        blob, hlines = None, []
        for c in port_history(port, int(pl)):
            b = show(c, rp)
            if b is not None:
                blob, hlines = c, lset(b, quote)
                break
        fenced = port.startswith(EXCL)
        if len(cands) == 1:
            plan.append((cls, port, pl, rp, cl, cands[0], blob, ",".join(map(str, hlines)),
                         "UNIQUE-IN-HEAD", quote, ltext(head, cands[0])))
        else:
            picks.append((cls, port, pl, rp, cl, quote, blob, hlines, cands, fenced))
    with open(os.path.join(ROOT, ".agents/slop/stale269/plan.tsv"), "w", encoding="utf-8") as fh:
        fh.write("class\tport\tpl\trp\tcl\tnew\tblob\thist\twhy\tquote\tnewline\n")
        for p in plan:
            fh.write("\t".join(str(x) for x in p) + "\n")
    print(f"  PLANNED {len(plan)} (unique in HEAD), NEEDS A PICK {len(picks)}")
    for cls, port, pl, rp, cl, quote, blob, hlines, cands, *rest in picks:
        fenced = rest[0] if rest else False
        print(f"\n===== {port}:{pl}  {cls}  {rp}:{cl} -> candidates {cands}"
              f"{'   [FENCED: ' + str(fenced) + ']' if fenced else ''}")
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        for i in range(max(0, int(pl) - 1), min(len(src), int(pl) + 2)):
            print(f"  CLAIM  {port}:{i+1}  {src[i].strip()[:175]}")
        print(f"  QUOTE  `{quote}`")
        print(f"  BLOB   {blob}  quote sat at {hlines} there")
        head = show("HEAD", rp) or ""
        for c in cands:
            print(f"  cand {c:5d}  {ltext(head, c)[:165]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))