#!/usr/bin/env python3
"""THE TIE-BREAK THAT IS NOT "NEAREST OCCURRENCE AT HEAD". **NEAREST IN THE BLOB**, then a reader.

    .venv/bin/python .agents/slop/stale269/ambig.py rows.tsv CLASS [SUBSTR]

For an `AMBIG` row the quote sits on SEVERAL lines of the cited file, and the number the comment
names is not one of them. Two questions, and they are different:

* **which occurrence did the AUTHOR mean?** -- answered in the BLOB, by distance from the cited
  number, because in the blob the cited number and its neighbours are the author's own coordinate
  system. Proximity in the blob is evidence about intent; proximity at HEAD is evidence about
  nothing, because HEAD's line numbers are the thing that moved.
* **where did THAT occurrence go?** -- answered by the whole line's text at HEAD.

Output per row: the blob occurrences with their distance from the cited number, the chosen blob
line pasted, and its HEAD address pasted. `NEAREST-IN-BLOB` is a PROPOSAL and the reader confirms
it against the CLAIM; `--all` prints every blob candidate so the proposal can be overridden.
"""
import difflib
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def show(commit: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{commit}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def port_history(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def hits(body: str, q: str) -> list[int]:
    return sorted({body[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(q), body)})


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def lt(body: str, n: int) -> str:
    ls = body.splitlines()
    return ls[n - 1] if 0 < n <= len(ls) else ""


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want = argv[2]
    idx = G.python_files()
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls != want:
            continue
        tgt = G.resolve(name, port, idx)
        if tgt is None:
            continue
        rp = os.path.relpath(tgt, ROOT)
        blob = hb = None
        for c in port_history(port, int(pl)):
            b = show(c, rp)
            if b is not None:
                blob, hb = c, b
                break
        if hb is None:
            continue
        bq = hits(hb, quote)
        if int(cl) in bq or len(bq) < 2:
            continue
        head = show("HEAD", rp) or ""
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        ranked = sorted(bq, key=lambda n: (abs(n - int(cl)), n))
        print(f"\n===== {port}:{pl}  {rp}:{cl}  quote `{quote}`")
        print(f"  CLAIM  {src[int(pl) - 1].strip()[:175]}")
        print(f"  BLOB   {blob}: occurrences {bq}")
        for n in bq:
            print(f"    blob {n:5d} d={abs(n - int(cl)):4d}  {lt(hb, n).strip()[:150]}")
        pick = ranked[0]
        key = norm(lt(hb, pick))
        ex = [n for n in hits(head, quote) if norm(lt(head, n)) == key]
        if ex:
            print(f"  PICK   blob {pick} -> HEAD {rp}:{ex[0]}  {lt(head, ex[0]).strip()[:150]}")
        else:
            sc = sorted(((difflib.SequenceMatcher(None, key, norm(lt(head, n))).ratio(), n)
                         for n in hits(head, quote)), reverse=True)
            if sc and sc[0][0] >= 0.9:
                print(f"  PICK   blob {pick} -> HEAD {rp}:{sc[0][1]} (sim {sc[0][0]:.3f})  "
                      f"{lt(head, sc[0][1]).strip()[:150]}")
            else:
                print(f"  PICK   blob {pick} -> NO WHOLE-LINE MATCH AT HEAD (best {sc[0][0]:.3f} "
                      f"at {sc[0][1] if sc else '-'}); READ IT")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))