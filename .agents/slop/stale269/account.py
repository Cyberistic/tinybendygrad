#!/usr/bin/env python3
"""THE ACCOUNTING. One row per census finding, one VERDICT per row, and the arithmetic closes.

    .venv/bin/python .agents/slop/stale269/account.py rows.tsv

Verdicts, and each is a DIFFERENT action, which is the point -- the census counted all 326 as
"RESTORE" and they are not one action:

| verdict | n | action |
|---|---:|---|
| `RESTORE`           | | retype the number to the line that says the thing. CONTENT- and HISTORY-anchored. |
| `NOT-BROKEN`        | | a RANGE citation whose text is inside the range. The gate reads only the range start. |
| `FENCED`            | | `ops.bend` / `fold.bend` / `helpers.bend`. NAMED, not edited. |
| `DECLINED`          | | restoring would require INVENTING something. |
| `AUTHOR`            | | the rule is gone. Not mine. |

`rows.tsv` is the GATE'S OWN output, so this file never re-decides what text a comment claims; it
only applies the range test the gate does not, and routes the rows to an owner.
"""
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
EXCL = ("tinybendygrad/uop/ops.bend", "tinybendygrad/uop/fold.bend",
        "tinybendygrad/helpers.bend", "tinybendygrad/graphcmp.bend")
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    idx = G.python_files()
    tally: dict[str, dict[str, int]] = {}
    out = []
    for f in rows:
        cls, port, pl, name, cl, near, dist, occ, other, quote = f.split("\t")
        if cls not in ("STALE-LINE", "WRONG-FILE", "NO-FILE", "PAST-EOF"):
            continue
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        m = next((c for c in CITE.finditer(src[int(pl) - 1]) if c.group(1) == name), None)
        tgt = G.resolve(name, port, idx)
        inside = ""
        if m is not None and m.group(3) is not None and tgt is not None:
            lo, hi = int(m.group(2)), int(m.group(3))
            head = open(tgt, encoding="utf-8", errors="replace").read()
            hit = sorted({head[: x.start()].count("\n") + 1
                          for x in re.finditer(re.escape(quote), head) if lo <= head[: x.start()].count("\n") + 1 <= hi})
            if hit:
                inside = ",".join(map(str, hit))
        if port.startswith(EXCL):
            v = "FENCED"
        elif inside:
            v = "NOT-BROKEN"
        else:
            v = cls
        tally.setdefault(v, {})
        tally[v]["total"] = tally[v].get("total", 0) + 1
        if port.startswith(EXCL):
            tally[v]["fenced"] = tally[v].get("fenced", 0) + 1
        out.append((v, cls, port, pl, name, cl, near, inside, quote, src[int(pl) - 1].strip()))
    with open(os.path.join(ROOT, ".agents/slop/stale269/ledger.tsv"), "w", encoding="utf-8") as fh:
        fh.write("verdict\tcensus\tport\tpl\tname\tcl\tnearest\tinrange\tquote\tclaim\n")
        for o in out:
            fh.write("\t".join(str(x).replace("\t", " ") for x in o) + "\n")
    for v, d in sorted(tally.items()):
        print(f"  {v:12} {d['total']:4d}" + (f"   ({d['fenced']} fenced, NOT EDITED)" if "fenced" in d else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))