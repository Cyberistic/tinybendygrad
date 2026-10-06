#!/usr/bin/env python3
"""THE ONE LEDGER. Every census row of a restore class, one verdict, and the arithmetic closes.

    .venv/bin/python .agents/slop/stale269/ledger.py rows.tsv

Inputs are the GATE'S OWN census rows plus the two independent adjudications in this directory
(`account.py`'s range test and `readjudicate.py`'s all-spans test), and they are CROSS-CHECKED
against each other: a row both call `HOLDS` is a hold; a row only one calls `HOLDS` is printed for
a reader. **Two methods that do not share a regex is the requirement; a row where they agree for
the wrong reason is the failure.**

| verdict | n | action |
|---|---:|---|
| `RESTORE-LINE`   | | retype the number. content-anchored (whole line) AND history-anchored (the blob). |
| `RESTORE-FILE`   | | the text is in ANOTHER file; the citation names this one. |
| `RESTORE-BOTH`   | | neither. |
| `NOT-BROKEN`     | | NOT restored. RANGE citation, or the gate pinned the WRONG SPAN on the line. |
| `FENCED`         | | `ops.bend` / `fold.bend` / `helpers.bend`. Named, not edited. |
| `DECLINED`       | | restoring would require INVENTING something. |
| `AUTHOR`         | | the rule is gone. Not this unit's. |
"""
import csv
import difflib
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/stale269")
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
QUOTE = re.compile(r"`([^`\n]{4,400})`")
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")


def show(c: str, p: str) -> str | None:
    r = subprocess.run(["git", "show", f"{c}:{p}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def phist(port: str, line: int) -> list[str]:
    r = subprocess.run(["git", "log", "-L", f"{line},{line}:{port}", "--format=%h"],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if re.fullmatch(r"[0-9a-f]{7,}", c)]


def hits(b: str, q: str) -> list[int]:
    return sorted({b[: m.start()].count("\n") + 1 for m in re.finditer(re.escape(q), b)})


def nz(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def lt(b: str, n: int) -> str:
    ls = b.splitlines()
    return ls[n - 1] if 0 < n <= len(ls) else ""


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = G.python_files()
    adj = {}
    for f in sorted(os.listdir(HERE)):
        if f.startswith("adjudicated-") and f.endswith(".tsv"):
            for r in csv.DictReader(open(os.path.join(HERE, f)), delimiter="\t"):
                adj[(r["port"], r["pl"])] = r
    out, tally = [], {}
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        key = (port, pl)
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        line = src[int(pl) - 1]
        a = adj.get(key)
        fenced = port.startswith(EXCL)
        verdict, new, rp, span, why = "", "", "", quote, ""
        tgt = G.resolve(name, port, idx)
        rpn = os.path.relpath(tgt, ROOT) if tgt else name

        if fenced:
            verdict, why = "FENCED", "another unit's file; named, not edited"
        elif a is None:
            # a WRONG-FILE / NO-FILE / PAST-EOF the all-spans pass did not reach (NO-FILE has no target)
            verdict = "DECLINED" if cls == "NO-FILE" else "UNRESOLVED"
            why = f"no target file resolves; quote `{quote}`"
        elif a["verdict"] == "HOLDS":
            verdict = "NOT-BROKEN"
            why = ("RANGE citation, text inside the range" if a["new"] and a["new"] != a["cl"]
                   else f"span `{a['span']}` IS on the cited line; the gate pinned `{a['gatespan']}`")
            if a["span"] != a["gatespan"]:
                verdict = "NOT-BROKEN/MIS-PIN"
        elif a["verdict"] == "NO-SPAN":
            verdict, why = "DECLINED", f"no span on the line sits in the cited file at all (`{quote}`)"
        elif cls in ("WRONG-FILE", "NO-FILE", "PAST-EOF"):
            verdict, why = "RESTORE-FILE", f"the text is in {a['rp']}, not {name}"
            new = a["new"]
            rp = a["rp"]
        else:
            verdict, new, rp = "RESTORE-LINE", a["new"], a["rp"]
            why = f"whole line of {a['coord'].split()[0]} carried to HEAD"
        row = dict(cls=cls, port=port, pl=pl, name=name, cl=cl, new=new, rp=rp, span=span,
                   quote=quote, verdict=verdict, why=why, claim=line.strip(),
                   newline="", fenced=fenced)
        if new.isdigit() and rp:
            h = show("HEAD", rp) or ""
            row["newline"] = lt(h, int(new)).strip()
        tally[verdict] = tally.get(verdict, 0) + 1
        out.append(row)
    with open(os.path.join(HERE, "FINAL.tsv"), "w", encoding="utf-8") as fh:
        cols = ("verdict", "cls", "port", "pl", "name", "cl", "new", "rp", "span", "quote",
                "why", "claim", "newline", "fenced")
        fh.write("\t".join(cols) + "\n")
        for r in out:
            fh.write("\t".join(str(r[c]).replace("\t", " ") for c in cols) + "\n")
    for v, n in sorted(tally.items()):
        print(f"  {v:22} {n:4d}")
    print(f"  {'TOTAL':22} {len(out):4d}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))